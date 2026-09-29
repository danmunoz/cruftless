import Darwin
import Foundation

public protocol SimulatorCommandExecuting: Sendable {
    func shutdownSimulator(udid: String) async throws
    func eraseSimulator(udid: String) async throws
    func deleteSimulator(udid: String) async throws
    func deleteRuntime(identifier: String) async throws
}

public struct DefaultSimulatorCommandExecutor: SimulatorCommandExecuting {
    private let runner: SimctlRunner

    public init(runner: SimctlRunner = SimctlRunner()) {
        self.runner = runner
    }

    public func shutdownSimulator(udid: String) async throws {
        try await runner.shutdown(udid: udid)
    }

    public func eraseSimulator(udid: String) async throws {
        try await runner.erase(udid: udid)
    }

    public func deleteSimulator(udid: String) async throws {
        try await runner.delete(udid: udid)
    }

    /// Sends the delete and then waits for the runtime to actually leave the installed list.
    public func deleteRuntime(identifier: String) async throws {
        try await runner.runtimeDelete(identifier: identifier)
        try await runner.awaitRuntimeRemoval(identifier: identifier)
    }
}

/// The sole executor permitted to permanently delete files or mutate simulators.
public actor DeletionExecutor {
    private let simulatorExecutor: SimulatorCommandExecuting
    let policyGenerationAuthority: PolicyGenerationAuthority
    let protectedPathsStore: ProtectedPathsStore
    let capacitySampler: @Sendable () async -> Int64
    let deviceDirectoryProvider: @Sendable (String) -> URL?
    let settleSleep: @Sendable () async throws -> Void
    var onProgress: (@Sendable (DeletionProgress) -> Void)?

    /// Serialises every overlapping `execute` call.
    var isExecuting = false

    private static let fileSystemQueue = DispatchQueue(
        label: "com.cruftless.core.deletion-executor",
        qos: .userInitiated
    )

    public init(
        simulatorExecutor: SimulatorCommandExecuting = DefaultSimulatorCommandExecutor(),
        policyGenerationAuthority: PolicyGenerationAuthority = PolicyGenerationAuthority(),
        protectedPathsStore: ProtectedPathsStore = .shared,
        capacitySampler: @escaping @Sendable () async -> Int64 = { VolumeCapacity.query().freeBytes },
        deviceDirectory: @escaping @Sendable (String) -> URL? = { udid in
            RootResolver.simulatorDevicesRoot().first?.appendingPathComponent(udid, isDirectory: true)
        },
        settleSleep: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(1)) }
    ) {
        self.simulatorExecutor = simulatorExecutor
        self.policyGenerationAuthority = policyGenerationAuthority
        self.protectedPathsStore = protectedPathsStore
        self.capacitySampler = capacitySampler
        deviceDirectoryProvider = deviceDirectory
        self.settleSleep = settleSleep
    }

    func executeSingle(
        _ target: DeletionTarget,
        affectedLocationIds: Set<String>,
        policyGeneration: UInt64,
        gradleCacheRiskAcknowledgement: GradleCacheRiskAcknowledgement?
    ) async -> ItemOutcome {
        switch target {
        case let .path(_, _, validatedPath, fingerprint, _, _, bytes, precondition):
            await executePath(PathDeletionRequest(
                target: target,
                validatedPath: validatedPath,
                fingerprint: fingerprint,
                bytes: bytes,
                precondition: precondition,
                affectedLocationIds: affectedLocationIds,
                policyGeneration: policyGeneration,
                gradleCacheRiskAcknowledgement: gradleCacheRiskAcknowledgement
            ))
        case let .simulatorErase(udid, _, isBooted, _, bytes):
            await executeSimulatorErase(target, udid: udid, isBooted: isBooted, bytes: bytes)
        case let .simulatorDelete(udid, _, isBooted, _, bytes):
            await executeSimulatorDelete(target, udid: udid, isBooted: isBooted, bytes: bytes)
        case let .runtimeDelete(identifier, _, _, bytes):
            await executeRuntimeDelete(target, identifier: identifier, bytes: bytes)
        }
    }

    /// Hops the whole check-then-delete sequence onto `fileSystemQueue`.
    /// Runs `work` on `fileSystemQueue` and suspends until it returns.
    static func offCooperativePool<Value: Sendable>(
        _ work: @escaping @Sendable () -> Value
    ) async -> Value {
        await withCheckedContinuation { continuation in
            fileSystemQueue.async {
                continuation.resume(returning: work())
            }
        }
    }

    package static func performPathDeletion(_ request: PathDeletionRequest) -> ItemOutcome {
        guard request.fingerprint.path == request.validatedPath.path else {
            return ItemOutcome(
                target: request.target,
                status: .failed(reason: "Refused: validated path and fingerprint disagree"),
                freedBytes: 0
            )
        }
        if let precondition = request.precondition, let refusal = check(precondition) {
            return ItemOutcome(target: request.target, status: .failed(reason: "Refused: \(refusal)"), freedBytes: 0)
        }
        guard request.revalidate() else {
            return ItemOutcome(
                target: request.target,
                status: .failed(reason: "Refused: tracked roots or protected paths changed after Review"),
                freedBytes: 0
            )
        }
        switch request.fingerprint.verify(at: request.validatedPath.url) {
        case .valid:
            let startedAt = Date()
            do {
                // Sole invocation of removeItem in the codebase.
                try FileManager.default.removeItem(at: request.validatedPath.url)
                return ItemOutcome(target: request.target, status: .succeeded, freedBytes: request.bytes)
            } catch {
                return outcomeAfterRemoveFailure(
                    target: request.target,
                    url: request.validatedPath.url,
                    plannedBytes: request.bytes,
                    startedAt: startedAt,
                    error: error
                )
            }
        case .missing:
            return ItemOutcome(target: request.target, status: .failed(reason: "Item no longer exists on disk"), freedBytes: 0)
        case let .pathChanged(expected, actual):
            return ItemOutcome(
                target: request.target,
                status: .failed(reason: "Resolved path changed: expected \(expected), got \(actual)"),
                freedBytes: 0
            )
        case let .changedSinceScan(reason):
            return ItemOutcome(target: request.target, status: .failed(reason: "Refused: \(reason)"), freedBytes: 0)
        }
    }

    /// Works out what a failed `removeItem` actually left behind.
    package static func outcomeAfterRemoveFailure(
        target: DeletionTarget,
        url: URL,
        plannedBytes: Int64,
        startedAt: Date,
        error: any Error
    ) -> ItemOutcome {
        var statBuf = stat()
        guard lstat(PathNormalizer.normalize(url.path(percentEncoded: false)), &statBuf) == 0 else {
            // Nothing is left despite the error: the delete did complete.
            return ItemOutcome(target: target, status: .succeeded, freedBytes: plannedBytes)
        }

        // A set of its own: this walk must count every byte still on disk, not skip the ones some earlier walk happened to see.
        let surviving = DirectoryWalker
            .walk(url: url, inodeSet: InodeSet(), ignoringEntriesCreatedAfter: startedAt)
            .allocatedBytes

        guard surviving > 0 else {
            // Nothing the plan named is still on disk.
            return ItemOutcome(target: target, status: .succeeded, freedBytes: plannedBytes)
        }

        let freed = max(0, plannedBytes - surviving)

        guard freed > 0 else {
            // Nothing came off.
            return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0)
        }

        let reason = "Partially removed: \(Self.sentence(error)) " +
            "\(ByteFormatter.format(surviving)) still on disk."
        return ItemOutcome(target: target, status: .partiallyFailed(reason: reason), freedBytes: freed)
    }

    /// Adds sentence-ending punctuation when needed.
    package static func sentence(_ error: any Error) -> String {
        let text = error.localizedDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return text.hasSuffix(".") ? text : text + "."
    }

    /// Re-checks a plan-time precondition at execute time.
    package static func check(_ precondition: DeletionPrecondition) -> String? {
        switch precondition {
        case let .simulatorShutdown(devicePlist, deviceName):
            let deviceDirectory = devicePlist.deletingLastPathComponent()
            guard let device = DeviceStore.parseDevicePlist(at: devicePlist, deviceDirectory: deviceDirectory) else {
                return "\(deviceName)'s device.plist can't be read, so its state is unknown"
            }
            guard device.state.isShutdown else {
                return "\(deviceName) is no longer shut down"
            }
            return nil
        }
    }

    private func executeSimulatorErase(
        _ target: DeletionTarget,
        udid: String,
        isBooted: Bool,
        bytes: Int64
    ) async -> ItemOutcome {
        report(DeletionProgress(verb: .erase, targetName: target.name, phase: .mutating))
        let baselineFree = await capacitySampler()
        do {
            if isBooted {
                try await simulatorExecutor.shutdownSimulator(udid: udid)
            }
            try await simulatorExecutor.eraseSimulator(udid: udid)
        } catch {
            return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0)
        }
        _ = await confirmEraseLanded(udid: udid)
        let settle = await waitForSpaceToSettle(
            verb: .erase, targetName: target.name, expectedBytes: bytes, baselineFreeBytes: baselineFree
        )
        return ItemOutcome(target: target, status: .succeeded, freedBytes: bytes, spaceSettle: settle)
    }

    private func executeSimulatorDelete(
        _ target: DeletionTarget,
        udid: String,
        isBooted: Bool,
        bytes: Int64
    ) async -> ItemOutcome {
        report(DeletionProgress(verb: .delete, targetName: target.name, phase: .mutating))
        let baselineFree = await capacitySampler()
        do {
            if isBooted {
                try await simulatorExecutor.shutdownSimulator(udid: udid)
            }
            try await simulatorExecutor.deleteSimulator(udid: udid)
        } catch {
            return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0)
        }
        _ = await confirmDeviceGone(udid: udid)
        let settle = await waitForSpaceToSettle(
            verb: .delete, targetName: target.name, expectedBytes: bytes, baselineFreeBytes: baselineFree
        )
        return ItemOutcome(target: target, status: .succeeded, freedBytes: bytes, spaceSettle: settle)
    }

    private func executeRuntimeDelete(_ target: DeletionTarget, identifier: String, bytes: Int64) async -> ItemOutcome {
        report(DeletionProgress(verb: .remove, targetName: target.name, phase: .mutating))
        let baselineFree = await capacitySampler()
        do {
            // Runtime deletion includes removal confirmation.
            try await simulatorExecutor.deleteRuntime(identifier: identifier)
        } catch {
            return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0)
        }
        let settle = await waitForSpaceToSettle(
            verb: .remove, targetName: target.name, expectedBytes: bytes, baselineFreeBytes: baselineFree
        )
        return ItemOutcome(target: target, status: .succeeded, freedBytes: bytes, spaceSettle: settle)
    }
}
