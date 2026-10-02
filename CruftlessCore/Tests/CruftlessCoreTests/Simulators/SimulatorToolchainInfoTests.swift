@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("Xcode bundle metadata bounds")
struct SimulatorToolchainInfoTests {
    @Test("Info.plist reads accept bounded regular files only")
    func boundedRegularFilesOnly() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("xcode-info-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let valid = root.appendingPathComponent("valid.plist")
        let info: [String: String] = ["CFBundleIdentifier": "com.apple.dt.Xcode"]
        let plist = try PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        try plist.write(to: valid)
        #expect(SimulatorToolchainResolver.readInfoDictionary(at: valid)?["CFBundleIdentifier"] as? String == "com.apple.dt.Xcode")

        let oversized = root.appendingPathComponent("oversized.plist")
        try Data(repeating: 0x20, count: 65_537).write(to: oversized)
        #expect(SimulatorToolchainResolver.readInfoDictionary(at: oversized) == nil)

        let link = root.appendingPathComponent("linked.plist")
        #expect(symlink(valid.path, link.path) == 0)
        #expect(SimulatorToolchainResolver.readInfoDictionary(at: link) == nil)

        let fifo = root.appendingPathComponent("fifo.plist")
        #expect(mkfifo(fifo.path, mode_t(0o600)) == 0)
        #expect(SimulatorToolchainResolver.readInfoDictionary(at: fifo) == nil)
    }
}
