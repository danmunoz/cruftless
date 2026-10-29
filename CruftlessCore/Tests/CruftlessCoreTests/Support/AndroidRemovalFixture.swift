@testable import CruftlessCore
import Darwin
import Foundation

struct AndroidRemovalFixture: Sendable {
    let root: URL
    let registry: URL
    let directory: URL
    let binary: URL
    let child: ChildEntry

    init(name: String = "Probe") throws {
        root = URL(fileURLWithPath: PathNormalizer.normalize(FileManager.default.temporaryDirectory
                .appendingPathComponent("cruftless-removal-\(UUID())", isDirectory: true).path(percentEncoded: false)), isDirectory: true)
        registry = root.appendingPathComponent(".android/avd", isDirectory: true)
        directory = registry.appendingPathComponent(name + ".avd", isDirectory: true)
        binary = root.appendingPathComponent("android-cli")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("test executable".utf8).write(to: binary)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: binary.path)
        try Data("path=\(directory.path)\npath.rel=avd/\(name).avd\ntarget=android-36\n".utf8)
            .write(to: registry.appendingPathComponent(name + ".ini"))
        try Data("AvdId=\(name)\nskin.path=\(root.path)/sdk/skins/pixel_9_pro\n".utf8)
            .write(to: directory.appendingPathComponent("config.ini"))
        try Data(repeating: 7, count: 16384).write(to: directory.appendingPathComponent("data"))
        child = ChildEntry(id: "androidAVDs-\(name)", name: name, url: directory,
                           reclaimableBytes: DirectoryWalker.walk(url: directory, inodeSet: InodeSet()).allocatedBytes,
                           staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
    }

    var protection: ProtectedPaths {
        ProtectedPaths(customProtectedPaths: [], home: root)
    }

    func cleanUp() {
        TestFileSystem.removeDirectoryRecursively(at: root)
    }

    func tools(
        candidates: [URL]? = nil,
        run: @escaping AndroidCLIProcess = { _, _, _, _ in
            BoundedProcess.Output(status: 0, stdoutData: Data("1.0.16625370\n".utf8), stderrData: Data())
        },
        download: @escaping @Sendable (URL, URL) async throws -> Void = { _, _ in
            throw AndroidAVDRemovalError.refused("Unexpected download")
        }
    ) -> AndroidCLITools {
        AndroidCLITools(home: root, androidUserHome: registry.deletingLastPathComponent(), sdk: root.appendingPathComponent("sdk"),
                        installDirectory: root.appendingPathComponent("tools"), candidates: candidates ?? [binary],
                        run: run, download: download)
    }

    func service(tools: AndroidCLITools, activity: @escaping AndroidCLIProcess = { _, _, _, _ in
        BoundedProcess.Output(status: 0, stdoutData: Data("/sbin/launchd launchd\n".utf8), stderrData: Data())
    }) -> AndroidAVDRemoval {
        AndroidAVDRemoval(tools: tools, registryRoot: registry, process: activity)
    }
}

extension AndroidRemovalFixture {
    func addDevice(named name: String) throws -> ChildEntry {
        let directory = registry.appendingPathComponent(name + ".avd", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("path=\(directory.path)\npath.rel=avd/\(name).avd\ntarget=android-36\n".utf8)
            .write(to: registry.appendingPathComponent(name + ".ini"))
        try Data("AvdId=\(name)\n".utf8).write(to: directory.appendingPathComponent("config.ini"))
        try Data(repeating: 7, count: 32768).write(to: directory.appendingPathComponent("data"))
        return ChildEntry(id: "androidAVDs-\(name)", name: name, url: directory,
                          reclaimableBytes: DirectoryWalker.walk(url: directory, inodeSet: InodeSet()).allocatedBytes,
                          staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
    }
}
