import Darwin
import Foundation

/// Removes one installed SDK package through `android sdk remove`, then confirms the result on disk.
public actor AndroidSDKPackageRemoval {
    nonisolated public let tools: AndroidCLITools
    public let avdRoots: [URL]
    private let process: AndroidCLIProcess
    private let removalTimeout: Duration
    private let accessGate: AccessGate

    public init(
        tools: AndroidCLITools = AndroidCLITools(),
        avdRoots: [URL]? = nil,
        removalTimeout: Duration = .seconds(180),
        accessGate: AccessGate = .shared,
        process: @escaping AndroidCLIProcess = { executable, arguments, environment, timeout in
            try await BoundedProcess.run(executable: executable, arguments: arguments, environment: environment, timeout: timeout)
        }
    ) {
        self.tools = tools
        self.avdRoots = avdRoots ?? RootResolver.androidAVDRoots()
        self.process = process
        self.removalTimeout = removalTimeout
        self.accessGate = accessGate
    }

    public func prepare(child: ChildEntry, protectedPaths: ProtectedPaths) async throws -> AndroidSDKPackageRemovalRequest {
        let identity = try AndroidSDKPackageRemovalIdentity.capture(child: child, sdkRoot: tools.sdk, protectedPaths: protectedPaths)
        let tool: AndroidCLITool
        switch await tools.availability(minimumVersion: .minimumForSDKRemoval) {
        case let .ready(ready): tool = ready
        case .setupRequired: throw AndroidAVDRemovalError.toolsRequired
        case let .updateRequired(installed): throw AndroidSDKPackageRemovalError.updateRequired(installed: installed)
        }
        try ensureUnreferenced(identity)
        try await ensureInactive(identity)
        try await ensureNoNestedMounts(identity)
        return AndroidSDKPackageRemovalRequest(identity: identity, tool: tool, displayName: child.name,
                                               estimatedBytes: child.reclaimableBytes)
    }

    package func remove(
        _ request: AndroidSDKPackageRemovalRequest,
        currentProtection: @escaping @Sendable () -> ProtectedPaths?
    ) async -> ItemOutcome {
        let target = DeletionTarget.androidSDKPackageDelete(request)
        do {
            guard let protectedPaths = currentProtection() else {
                throw AndroidAVDRemovalError.refused("Platform selection changed after Review. Review this package again.")
            }
            guard ProtectedPaths.normalize(request.identity.sdkRoot) == ProtectedPaths.normalize(tools.sdk) else {
                throw AndroidAVDRemovalError.refused("Android tools use a different SDK than the one reviewed.")
            }
            try request.identity.revalidate(protectedPaths: protectedPaths)
            try await tools.verify(request.tool, minimumVersion: .minimumForSDKRemoval)
            try ensureUnreferenced(request.identity)
            try await ensureInactive(request.identity)
            try await ensureNoNestedMounts(request.identity)
            guard let current = currentProtection() else {
                throw AndroidAVDRemovalError.refused("Platform selection changed after Review. Review this package again.")
            }
            try request.identity.revalidate(protectedPaths: current)
        } catch { return ItemOutcome(target: target, status: .failed(reason: error.localizedDescription), freedBytes: 0) }
        var failure: String?
        do {
            let output = try await tools.invoke(request.tool, arguments: ["sdk", "remove", request.identity.cliName],
                                                timeout: removalTimeout)
            if output.status != 0 { failure = "Android tools exited with code \(output.status)." }
        } catch { failure = "Package removal was interrupted or failed: \(error.localizedDescription)" }
        let reported = failure
        return await DeletionExecutor.offCooperativePool { Self.outcome(for: request, failure: reported) }
    }

    /// The CLI exits 0 when it removed nothing, so only what remains on disk decides the outcome.
    nonisolated static func outcome(for request: AndroidSDKPackageRemovalRequest, failure: String?) -> ItemOutcome {
        let target = DeletionTarget.androidSDKPackageDelete(request)
        var metadata = stat()
        if lstat(request.identity.directory.path(percentEncoded: false), &metadata) != 0 {
            guard errno == ENOENT || errno == ENOTDIR else {
                return ItemOutcome(target: target,
                                   status: .failed(reason: "Removal could not be confirmed because the SDK is unreadable."),
                                   freedBytes: 0)
            }
            return ItemOutcome(target: target, status: .succeeded, freedBytes: request.estimatedBytes)
        }
        let walk = DirectoryWalker.walk(url: request.identity.directory, inodeSet: InodeSet())
        let incomplete = walk.unreadableDirectoryCount > 0 || walk.skippedMountCount > 0
        let freed = incomplete ? 0 : max(0, request.estimatedBytes - walk.allocatedBytes)
        let remainder = incomplete
            ? "Remaining storage could not be fully measured."
            : "\(ByteFormatter.format(walk.allocatedBytes)) remains on disk."
        let reason = (failure ?? "Android tools did not remove this package.") + " " + remainder + " Rescan before trying again."
        return ItemOutcome(target: target, status: freed > 0 ? .partiallyFailed(reason: reason) : .failed(reason: reason),
                           freedBytes: freed)
    }

    /// Refuses a system image that a virtual device still names, since the CLI removes it without checking.
    func ensureUnreferenced(_ identity: AndroidSDKPackageRemovalIdentity) throws {
        guard identity.category == "system-images" else { return }
        guard let registry = avdRoots.first else { return }
        var registryStat = stat()
        guard lstat(registry.path(percentEncoded: false), &registryStat) == 0 else {
            guard errno == ENOENT else { throw AndroidSDKPackageRemovalError.devicesUnverifiable }
            return
        }
        guard let names = RootResolver.listAVDRegistry(registry, gate: accessGate) else {
            throw AndroidSDKPackageRemovalError.devicesUnverifiable
        }
        let registrations = names.filter { $0.hasSuffix(".ini") }
        guard registrations.count <= 256 else { throw AndroidSDKPackageRemovalError.devicesUnverifiable }
        let packageDirectory = ProtectedPaths.normalize(identity.directory)
        for registration in registrations {
            let device = try deviceImages(registration, in: registry)
            if device.images.contains(where: { Self.resolve($0, sdkRoot: identity.sdkRoot) == packageDirectory }) {
                throw AndroidSDKPackageRemovalError.usedByDevice(device.name)
            }
        }
    }

    /// Reads one registration's `image.sysdir.*` entries, refusing whatever cannot be read without asking for access.
    private func deviceImages(_ registration: String, in registry: URL) throws -> (name: String, images: [String]) {
        guard let text = RootResolver.boundedProperties(at: registry.appendingPathComponent(registration)) else {
            throw AndroidSDKPackageRemovalError.devicesUnverifiable
        }
        let values = RootResolver.propertyValues(text)
        let relative = values["path.rel"].flatMap { value -> URL? in
            guard !value.hasPrefix("/"), !value.contains("\0") else { return nil }
            return registry.deletingLastPathComponent().appendingPathComponent(value, isDirectory: true)
        }
        guard let directory = values["path"].flatMap(RootResolver.absoluteAndroidPath) ?? relative,
              accessGate.check(directory) == .clear,
              let config = RootResolver.boundedProperties(at: directory.appendingPathComponent("config.ini"))
        else { throw AndroidSDKPackageRemovalError.devicesUnverifiable }
        let configValues = RootResolver.propertyValues(config)
        let name = values["avd.ini.displayname"] ?? configValues["avd.ini.displayname"]
            ?? URL(fileURLWithPath: registration).deletingPathExtension().lastPathComponent
        return (name, configValues.filter { $0.key.hasPrefix("image.sysdir.") }.map(\.value))
    }

    private static func resolve(_ value: String, sdkRoot: URL) -> String {
        let url = value.hasPrefix("/")
            ? URL(fileURLWithPath: value, isDirectory: true)
            : sdkRoot.appendingPathComponent(value, isDirectory: true)
        return ProtectedPaths.normalize(url.standardizedFileURL)
    }

    /// Refuses while a process runs from inside the package or another SDK manager is working.
    public func ensureInactive(_ identity: AndroidSDKPackageRemovalIdentity) async throws {
        let output = try await process(URL(fileURLWithPath: "/bin/ps"), ["-axo", "comm=,args="],
                                       BoundedProcess.minimalEnvironment(), .seconds(5))
        guard output.status == 0, !output.stdout.isEmpty else {
            throw AndroidAVDRemovalError.refused("Running Android tools could not be checked. Try again.")
        }
        let inside = ProtectedPaths.normalize(identity.directory) + "/"
        let lexical = identity.directory.standardizedFileURL.path(percentEncoded: false)
        let lexicalInside = lexical.hasSuffix("/") ? lexical : lexical + "/"
        for line in output.stdout.split(whereSeparator: \.isNewline) {
            if line.contains(inside) || line.contains(lexicalInside) {
                throw AndroidSDKPackageRemovalError.inUse
            }
            if line.contains("sdkmanager") || line.contains("android-cli") && line.contains(" sdk ") {
                throw AndroidSDKPackageRemovalError.managerBusy
            }
        }
    }

    private func ensureNoNestedMounts(_ identity: AndroidSDKPackageRemovalIdentity) async throws {
        let walk = await DeletionExecutor.offCooperativePool {
            DirectoryWalker.walk(url: identity.directory, inodeSet: InodeSet())
        }
        guard walk.skippedMountCount == 0, walk.unreadableDirectoryCount == 0 else {
            throw AndroidAVDRemovalError
                .refused("This package contains an unreadable folder or mounted filesystem and remains read-only.")
        }
    }
}

public struct AndroidSDKPackageRemovalRequest: Sendable, Hashable {
    public let identity: AndroidSDKPackageRemovalIdentity
    public let tool: AndroidCLITool
    public let displayName: String
    public let estimatedBytes: Int64
}

public enum AndroidSDKPackageRemovalError: Error, LocalizedError, Sendable, Equatable {
    case updateRequired(installed: AndroidCLIVersion?)
    case usedByDevice(String)
    case devicesUnverifiable
    case inUse
    case managerBusy

    public var errorDescription: String? {
        switch self {
        case let .updateRequired(installed):
            "Removing SDK packages needs Android tools \(AndroidCLIVersion.minimumForSDKRemoval) or later"
                + (installed.map { "; \($0) is set up." } ?? ".")
        case let .usedByDevice(name):
            "\(name) uses this system image. Delete that virtual device first, or keep the image."
        case .devicesUnverifiable:
            "Virtual devices could not be checked for this system image, so it stays read-only."
        case .inUse:
            "Something is running from this package. Quit it, then try again."
        case .managerBusy:
            "Another SDK manager is running. Wait for it to finish, then try again."
        }
    }
}
