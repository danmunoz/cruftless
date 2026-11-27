@testable import CruftlessCore
import Foundation

/// A disposable home with an SDK at the default `Library/Android/sdk` location, so the guard's real exception is exercised.
struct AndroidSDKRemovalFixture: Sendable {
    static let latest = "1.1.16919734\n"
    static let outdated = "1.0.16261425\n\nA new version of Android CLI is available (1.1.16919734).\n"

    let root: URL
    let sdk: URL
    let registry: URL
    let binary: URL

    init() throws {
        root = URL(fileURLWithPath: PathNormalizer.normalize(FileManager.default.temporaryDirectory
                       .appendingPathComponent("cruftless-sdk-removal-\(UUID())", isDirectory: true).path(percentEncoded: false)),
        isDirectory: true)
        sdk = root.appendingPathComponent("Library/Android/sdk", isDirectory: true)
        registry = root.appendingPathComponent(".android/avd", isDirectory: true)
        binary = root.appendingPathComponent("android-cli")
        try FileManager.default.createDirectory(at: sdk, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: registry, withIntermediateDirectories: true)
        try Self.writeExecutable(at: binary)
    }

    var protection: ProtectedPaths {
        ProtectedPaths(customProtectedPaths: [], home: root)
    }

    var context: PlanningContext {
        PlanningContext(protectedPaths: protection)
    }

    func cleanUp() {
        TestFileSystem.removeDirectoryRecursively(at: root)
    }

    static func writeExecutable(at url: URL) throws {
        try Data("test executable".utf8).write(to: url)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
    }

    static func output(_ text: String, status: Int32 = 0) -> BoundedProcess.Output {
        BoundedProcess.Output(status: status, stdoutData: Data(text.utf8), stderrData: Data())
    }

    /// Writes an installed package whose `package.xml` names `identity`, defaulting to the folder's own path.
    @discardableResult
    func addPackage(_ relativePath: String, identity: String? = nil, bytes: Int = 32768) throws -> ChildEntry {
        let directory = sdk.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let path = identity ?? relativePath.replacingOccurrences(of: "/", with: ";")
        let xml = "<repository><localPackage path=\"\(path)\"><revision><major>35</major></revision></localPackage></repository>"
        try Data(xml.utf8).write(to: directory.appendingPathComponent("package.xml"))
        try Data(repeating: 3, count: bytes).write(to: directory.appendingPathComponent("payload"))
        return child(for: directory)
    }

    func child(for directory: URL) -> ChildEntry {
        ChildEntry(id: "androidSDK-" + ProtectedPaths.normalize(directory), name: directory.lastPathComponent, url: directory,
                   reclaimableBytes: DirectoryWalker.walk(url: directory, inodeSet: InodeSet()).allocatedBytes,
                   staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
    }

    /// Registers a virtual device whose config names `systemImage` as its first image directory.
    func addDevice(named name: String, systemImage: String) throws {
        let directory = registry.appendingPathComponent(name + ".avd", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("path=\(directory.path)\npath.rel=avd/\(name).avd\n".utf8)
            .write(to: registry.appendingPathComponent(name + ".ini"))
        try Data("AvdId=\(name)\nimage.sysdir.1=\(systemImage)\n".utf8).write(to: directory.appendingPathComponent("config.ini"))
    }

    func tools(
        candidates: [URL]? = nil,
        version: String = latest,
        onRemove: (@Sendable ([String]) async throws -> BoundedProcess.Output)? = nil,
        download: @escaping @Sendable (URL, URL) async throws -> Void = { _, _ in
            throw AndroidAVDRemovalError.refused("Unexpected download")
        }
    ) -> AndroidCLITools {
        AndroidCLITools(home: root, androidUserHome: registry.deletingLastPathComponent(), sdk: sdk,
                        installDirectory: root.appendingPathComponent("tools"), candidates: candidates ?? [binary],
                        run: { _, arguments, _, _ in
                            if arguments.contains("remove"), let onRemove { return try await onRemove(arguments) }
                            return Self.output(version)
                        },
                        download: download)
    }

    func service(
        tools: AndroidCLITools,
        processes: String = "/sbin/launchd launchd\n"
    ) -> AndroidSDKPackageRemoval {
        AndroidSDKPackageRemoval(tools: tools, avdRoots: [registry],
                                 process: { _, _, _, _ in Self.output(processes) })
    }

    func executor(_ service: AndroidSDKPackageRemoval) -> DeletionExecutor {
        let policy = PolicyGenerationAuthority()
        policy.update(to: 0, readOnlyLocationIDs: [LocationCatalog.androidSDK.id])
        return DeletionExecutor(androidSDKPackageRemoval: service, policyGenerationAuthority: policy)
    }
}
