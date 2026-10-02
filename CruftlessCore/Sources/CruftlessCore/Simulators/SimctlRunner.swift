import Foundation

public enum SimctlError: Error, Sendable, Equatable, LocalizedError {
    case nonZeroExit(exitCode: Int32, message: String)
    case invalidJSON(String)
    case executionError(String)
    case timedOut(String)
    case invalidIdentifier(String)
    case toolchainUnavailable(String)
    /// `simctl runtime delete` was accepted, but the runtime was still listed when the wait for it to actually go away ran out.
    case removalNotConfirmed(String)

    public var errorDescription: String? {
        switch self {
        case let .nonZeroExit(exitCode, message):
            "simctl exited with status \(exitCode): \(message)"
        case let .invalidJSON(detail):
            "simctl returned unparseable output: \(detail)"
        case let .executionError(detail):
            "simctl could not be launched: \(detail)"
        case let .timedOut(command):
            "simctl timed out running: \(command)"
        case let .invalidIdentifier(identifier):
            "Refused an unsafe simctl identifier: \(identifier)"
        case let .toolchainUnavailable(message):
            message
        case .removalNotConfirmed:
            """
            CoreSimulator accepted the delete but the runtime is still installed. \
            It may still be removing in the background: scan again in a minute to check.
            """
        }
    }
}

public struct SimctlOutput: Sendable {
    public let status: Int32
    public let stdout: String
    public let stderr: String
    public let toolchainID: String?
    public let toolchainGeneration: UUID?

    public init(
        status: Int32,
        stdout: String,
        stderr: String,
        toolchainID: String? = nil,
        toolchainGeneration: UUID? = nil
    ) {
        self.status = status
        self.stdout = stdout
        self.stderr = stderr
        self.toolchainID = toolchainID
        self.toolchainGeneration = toolchainGeneration
    }
}

public struct SimulatorRuntimeListing: Sendable {
    public let runtimes: [SimRuntime]
    public let toolchainID: String?
    public let toolchainGeneration: UUID?
    public let mutationIssue: String?

    public init(
        runtimes: [SimRuntime],
        toolchainID: String? = nil,
        toolchainGeneration: UUID? = nil,
        mutationIssue: String? = nil
    ) {
        self.runtimes = runtimes
        self.toolchainID = toolchainID
        self.toolchainGeneration = toolchainGeneration
        self.mutationIssue = mutationIssue
    }
}

public protocol SimctlExecuting: Sendable {
    func run(arguments: [String]) async throws -> SimctlOutput
}

/// Thin adapter binding `BoundedProcess` to `/usr/bin/xcrun simctl` plus the environment policy `simctl` needs.
public struct DefaultSimctlExecutor: SimctlExecuting {
    /// Ceiling on a single `simctl` invocation.
    public static let defaultTimeout: Duration = .seconds(120)

    private let timeout: Duration
    private let executableURL: URL
    private let argumentPrefix: [String]
    private let onLaunch: (@Sendable (pid_t) -> Void)?
    private let toolchainResolver: SimulatorToolchainResolver?

    public init(timeout: Duration = DefaultSimctlExecutor.defaultTimeout) {
        self.init(
            timeout: timeout,
            executableURL: URL(fileURLWithPath: "/usr/bin/xcrun"),
            argumentPrefix: ["simctl"],
            toolchainResolver: .shared
        )
    }

    package init(
        timeout: Duration,
        executableURL: URL,
        argumentPrefix: [String],
        onLaunch: (@Sendable (pid_t) -> Void)? = nil,
        toolchainResolver: SimulatorToolchainResolver? = nil
    ) {
        self.timeout = timeout
        self.executableURL = executableURL
        self.argumentPrefix = argumentPrefix
        self.onLaunch = onLaunch
        self.toolchainResolver = toolchainResolver
    }

    public func run(arguments: [String]) async throws -> SimctlOutput {
        let developerDirectory: URL?
        let toolchainID: String?
        let toolchainGeneration: UUID?
        if let toolchainResolver {
            let resolution = await toolchainResolver.resolve()
            guard let toolchain = resolution.toolchain else {
                throw SimctlError.toolchainUnavailable(
                    resolution.failure?.localizedDescription ?? SimulatorToolchainFailure.unavailable.localizedDescription
                )
            }
            developerDirectory = toolchain.developerDirectory
            toolchainID = toolchain.id
            toolchainGeneration = resolution.generation
        } else {
            developerDirectory = nil
            toolchainID = nil
            toolchainGeneration = nil
        }
        do {
            let output = try await BoundedProcess.run(
                executable: executableURL,
                arguments: argumentPrefix + arguments,
                environment: Self.childEnvironment(developerDirectory: developerDirectory),
                timeout: timeout,
                onLaunch: onLaunch
            )
            return SimctlOutput(
                status: output.status,
                stdout: output.stdout,
                stderr: output.stderr,
                toolchainID: toolchainID,
                toolchainGeneration: toolchainGeneration
            )
        } catch let error as BoundedProcess.RunError {
            switch error {
            case let .executionFailed(message):
                throw SimctlError.executionError(message)
            case .timedOut:
                throw SimctlError.timedOut(arguments.joined(separator: " "))
            }
        }
    }

    fileprivate func beginsToolchainOperation(generation: UUID) async -> Bool {
        guard let toolchainResolver else { return false }
        return await toolchainResolver.beginOperation(generation: generation)
    }

    fileprivate func endsToolchainOperation(generation: UUID) async {
        await toolchainResolver?.endOperation(generation: generation)
    }

    package static func childEnvironment(
        from inherited: [String: String] = ProcessInfo.processInfo.environment,
        developerDirectory: URL? = nil
    ) -> [String: String] {
        var environment = BoundedProcess.minimalEnvironment(from: inherited)
        if let developerDirectory {
            environment["DEVELOPER_DIR"] = developerDirectory.path
        }
        return environment
    }
}

/// Safely runs `simctl` subcommands with typed errors and JSON parsing.
public struct SimctlRunner: Sendable {
    package typealias DeviceStateReader = @Sendable (String) -> SimDeviceState?

    private let executor: any SimctlExecuting
    private let deviceStateReader: DeviceStateReader

    public init(executor: any SimctlExecuting = DefaultSimctlExecutor()) {
        self.init(executor: executor, deviceStateReader: Self.readDeviceState)
    }

    package init(executor: any SimctlExecuting, deviceStateReader: @escaping DeviceStateReader) {
        self.executor = executor
        self.deviceStateReader = deviceStateReader
    }

    private static func readDeviceState(udid: String) -> SimDeviceState? {
        guard let devicesRoot = RootResolver.simulatorDevicesRoot().first else { return nil }
        let deviceDirectory = devicesRoot.appendingPathComponent(udid, isDirectory: true)
        let plistURL = deviceDirectory.appendingPathComponent("device.plist")
        return DeviceStore.parseDevicePlist(at: plistURL, deviceDirectory: deviceDirectory)?.state
    }

    public func listRuntimes() async throws -> [SimRuntime] {
        (try await listRuntimeCatalog()).runtimes
    }

    public func listRuntimeCatalog() async throws -> SimulatorRuntimeListing {
        let output = try await executor.run(arguments: ["runtime", "list", "-j"])
        guard output.status == 0 else {
            throw SimctlError.nonZeroExit(
                exitCode: output.status,
                message: output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }

        guard let data = output.stdout.data(using: .utf8) else {
            throw SimctlError.invalidJSON("Empty or non-UTF8 output")
        }

        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: [String: Any]] else {
            throw SimctlError.invalidJSON("Expected JSON dictionary keyed by runtime UUID")
        }

        var runtimes: [SimRuntime] = []

        for (uuid, dict) in json {
            let runtimeId = dict["runtimeIdentifier"] as? String ?? dict["identifier"] as? String ?? uuid
            let build = dict["build"] as? String ?? ""
            let sizeBytes = dict["sizeBytes"] as? Int64 ?? (dict["sizeBytes"] as? NSNumber)?.int64Value ?? 0
            let deletable = dict["deletable"] as? Bool ?? true
            let state = SimRuntimeState(simctlValue: dict["state"] as? String)

            let friendlyName = Naming.runtime(identifier: runtimeId, build: build)

            runtimes.append(
                SimRuntime(
                    identifier: uuid,
                    runtimeIdentifier: runtimeId,
                    name: friendlyName,
                    build: build,
                    sizeBytes: sizeBytes,
                    isDeletable: deletable,
                    state: state,
                    toolchainID: output.toolchainID,
                    toolchainGeneration: output.toolchainGeneration
                )
            )
        }

        return SimulatorRuntimeListing(
            runtimes: runtimes.sorted { $0.sizeBytes > $1.sizeBytes },
            toolchainID: output.toolchainID,
            toolchainGeneration: output.toolchainGeneration
        )
    }

    public func beginsToolchainOperation(generation: UUID?) async -> Bool {
        guard let generation else { return false }
        guard let executor = executor as? DefaultSimctlExecutor else { return true }
        return await executor.beginsToolchainOperation(generation: generation)
    }

    public func endsToolchainOperation(generation: UUID?) async {
        guard let generation, let executor = executor as? DefaultSimctlExecutor else { return }
        await executor.endsToolchainOperation(generation: generation)
    }

    /// Shuts a device down, treating "already shut down" as success.
    public func shutdown(udid: String) async throws {
        let udid = try SimctlIdentifier.validatedUDID(udid)
        let output = try await executor.run(arguments: ["shutdown", udid])
        guard output.status != 0 else { return }

        let message = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
        if message.localizedCaseInsensitiveContains("current state: Shutdown") {
            return
        }
        if deviceStateReader(udid)?.isShutdown == true {
            return
        }
        throw SimctlError.nonZeroExit(exitCode: output.status, message: message)
    }

    public func erase(udid: String) async throws {
        let udid = try SimctlIdentifier.validatedUDID(udid)
        let output = try await executor.run(arguments: ["erase", udid])
        if output.status != 0 {
            throw SimctlError.nonZeroExit(exitCode: output.status, message: output.stderr)
        }
    }

    public func delete(udid: String) async throws {
        let udid = try SimctlIdentifier.validatedUDID(udid)
        let output = try await executor.run(arguments: ["delete", udid])
        if output.status != 0 {
            throw SimctlError.nonZeroExit(exitCode: output.status, message: output.stderr)
        }
    }

    public func runtimeDelete(identifier: String) async throws {
        let identifier = try SimctlIdentifier.validatedRuntime(identifier)
        let output = try await executor.run(arguments: ["runtime", "delete", identifier])
        if output.status != 0 {
            throw SimctlError.nonZeroExit(exitCode: output.status, message: output.stderr)
        }
    }

    public func awaitRuntimeRemoval(
        identifier: String,
        timeout: Duration = Self.removalConfirmationTimeout,
        pollInterval: Duration = Self.removalPollInterval
    ) async throws {
        let identifier = try SimctlIdentifier.validatedRuntime(identifier)
        let deadline = ContinuousClock.now.advanced(by: timeout)

        while true {
            if await isRuntimeGone(identifier) { return }
            guard ContinuousClock.now < deadline else {
                throw SimctlError.removalNotConfirmed(identifier)
            }
            do {
                try await Task.sleep(for: pollInterval)
            } catch {
                throw SimctlError.removalNotConfirmed(identifier)
            }
        }
    }

    private func isRuntimeGone(_ identifier: String) async -> Bool {
        guard let runtimes = try? await listRuntimes() else { return false }
        return !runtimes.contains { $0.matches(identifier) }
    }

    /// How long `awaitRuntimeRemoval` waits before giving up.
    public static let removalConfirmationTimeout: Duration = .seconds(90)
    /// Each poll spawns a `simctl runtime list`, so this is a gap between lookups, not a busy-wait.
    public static let removalPollInterval: Duration = .seconds(1)
}

extension SimRuntime {
    /// Whether this runtime is the one `identifier` names.
    func matches(_ identifier: String) -> Bool {
        self.identifier.caseInsensitiveCompare(identifier) == .orderedSame
            || runtimeIdentifier.caseInsensitiveCompare(identifier) == .orderedSame
    }
}
