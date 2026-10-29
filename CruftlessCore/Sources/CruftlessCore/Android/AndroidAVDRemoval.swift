import Darwin
import Foundation

public actor AndroidAVDRemoval {
    public let tools: AndroidCLITools
    public let registryRoot: URL
    private let process: AndroidCLIProcess
    private let removalTimeout: Duration

    public init(
        tools: AndroidCLITools = AndroidCLITools(),
        registryRoot: URL? = nil,
        removalTimeout: Duration = .seconds(120),
        process: @escaping AndroidCLIProcess = { executable, arguments, environment, timeout in
            try await BoundedProcess.run(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
        }
    ) {
        self.tools = tools
        self.registryRoot = registryRoot ?? RootResolver.androidAVDRoots().first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".android/avd", isDirectory: true)
        self.process = process
        self.removalTimeout = removalTimeout
    }

    public func prepare(child: ChildEntry, protectedPaths: ProtectedPaths) async throws -> AndroidAVDRemovalRequest {
        let identity = try AndroidAVDRemovalIdentity.capture(child: child, registryRoot: registryRoot, protectedPaths: protectedPaths)
        guard case let .ready(tool) = await tools.availability() else { throw AndroidAVDRemovalError.toolsRequired }
        try await ensureInactive(identity)
        try await ensureNoNestedMounts(identity)
        guard ProtectedPaths.normalize(registryRoot.deletingLastPathComponent()) == ProtectedPaths.normalize(tools.androidUserHome) else {
            throw AndroidAVDRemovalError.refused("Android tools use a different device registry. This device remains read-only.")
        }
        return AndroidAVDRemovalRequest(identity: identity, tool: tool, displayName: child.name, estimatedBytes: child.reclaimableBytes)
    }

    package func remove(
        _ request: AndroidAVDRemovalRequest,
        currentProtection: @escaping @Sendable () -> ProtectedPaths?
    ) async -> ItemOutcome {
        let target = DeletionTarget.androidAVDDelete(request)
        do {
            guard let protectedPaths = currentProtection() else {
                throw AndroidAVDRemovalError.refused("Platform selection changed after Review. Review this device again.")
            }
            guard request.identity.registryRoot == registryRoot,
                  ProtectedPaths.normalize(registryRoot.deletingLastPathComponent()) == ProtectedPaths.normalize(tools.androidUserHome)
            else { throw AndroidAVDRemovalError.refused("The Android device registry changed after Review.") }
            try request.identity.revalidate(protectedPaths: protectedPaths)
            try await tools.verify(request.tool)
            try await ensureNoNestedMounts(request.identity)
            try await ensureInactive(request.identity)
            guard let current = currentProtection() else {
                throw AndroidAVDRemovalError.refused("Platform selection changed after Review. Review this device again.")
            }
            try request.identity.revalidate(protectedPaths: current)
        } catch { return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0) }
        var errorText: String?
        do {
            let output = try await tools.invoke(
                request.tool,
                arguments: ["emulator", "remove", request.identity.name],
                timeout: removalTimeout
            )
            if output.status != 0 { errorText = "Android tools exited with code \(output.status)." }
        } catch { errorText = "Android device removal was interrupted or failed: \(error.localizedDescription)" }
        let failure = errorText
        return await DeletionExecutor.offCooperativePool { Self.outcome(for: request, failure: failure) }
    }

    nonisolated private static func outcome(for request: AndroidAVDRemovalRequest, failure: String?) -> ItemOutcome {
        let target = DeletionTarget.androidAVDDelete(request)
        guard let directoryExists = Self.presence(request.identity.directory),
              let registryExists = Self.presence(request.identity.registry) else {
            return ItemOutcome(
                target: target,
                status: .failed(reason: "Removal could not be confirmed because device storage is unreadable."),
                freedBytes: 0
            )
        }
        if !directoryExists, !registryExists {
            return ItemOutcome(target: target, status: .succeeded, freedBytes: request.estimatedBytes)
        }
        let remainingWalk = directoryExists
            ? DirectoryWalker.walk(url: request.identity.directory, inodeSet: InodeSet()) : nil
        let remaining = remainingWalk?.allocatedBytes ?? 0
        let measurementIncomplete = (remainingWalk?.unreadableDirectoryCount ?? 0) > 0
            || (remainingWalk?.skippedMountCount ?? 0) > 0
        let freed = measurementIncomplete ? 0 : max(0, request.estimatedBytes - remaining)
        let remainder = measurementIncomplete
            ? "Remaining storage could not be fully measured."
            : "\(ByteFormatter.format(remaining)) remains on disk."
        let reason = (failure ?? "Android tools did not completely remove this device.")
            + " " + remainder + " Rescan before trying again."
        return ItemOutcome(target: target,
                           status: (!registryExists || freed > 0) ? .partiallyFailed(reason: reason) : .failed(reason: reason),
                           freedBytes: freed)
    }

    nonisolated private static func presence(_ url: URL) -> Bool? {
        var metadata = stat()
        if lstat(url.path(percentEncoded: false), &metadata) == 0 { return true }
        return errno == ENOENT || errno == ENOTDIR ? false : nil
    }

    private func ensureNoNestedMounts(_ identity: AndroidAVDRemovalIdentity) async throws {
        let walk = await DeletionExecutor.offCooperativePool {
            DirectoryWalker.walk(url: identity.directory, inodeSet: InodeSet())
        }
        guard walk.skippedMountCount == 0, walk.unreadableDirectoryCount == 0 else {
            throw AndroidAVDRemovalError
                .refused("Device storage contains an unreadable directory or mounted filesystem and remains read-only.")
        }
    }

    public func ensureInactive(_ identity: AndroidAVDRemovalIdentity) async throws {
        let output = try await process(URL(fileURLWithPath: "/bin/ps"), ["-axo", "comm=,args="],
                                       BoundedProcess.minimalEnvironment(), .seconds(5))
        guard output.status == 0, !output.stdout.isEmpty else {
            throw AndroidAVDRemovalError.refused("The emulator's activity could not be checked. Try again.")
        }
        let escaped = NSRegularExpression.escapedPattern(for: identity.name)
        let pattern = #"(?:-avd\s+|@)"# + escaped + #"(?:\s|$)"#
        for line in output.stdout.split(whereSeparator: \.isNewline) {
            if line.contains("qemu-system") || line.contains("/emulator"),
               String(line).range(of: pattern, options: .regularExpression) != nil
               || line.contains(identity.directory.path(percentEncoded: false)) {
                throw AndroidAVDRemovalError.refused("This emulator is active. Shut it down before deleting its device.")
            }
        }
        let path = identity.directory.appendingPathComponent("multiinstance.lock").path(percentEncoded: false)
        let descriptor = open(path, O_RDWR | O_NOFOLLOW | O_CLOEXEC)
        if descriptor < 0 {
            guard errno == ENOENT else { throw AndroidAVDRemovalError.refused("The emulator's activity could not be verified.") }
            return
        }
        defer { close(descriptor) }
        guard flock(descriptor, LOCK_EX | LOCK_NB) == 0 else {
            throw AndroidAVDRemovalError.refused("This emulator is active. Shut it down before deleting its device.")
        }
        flock(descriptor, LOCK_UN)
    }
}

public struct AndroidAVDRemovalRequest: Sendable, Hashable {
    public let identity: AndroidAVDRemovalIdentity
    public let tool: AndroidCLITool
    public let displayName: String
    public let estimatedBytes: Int64
}
