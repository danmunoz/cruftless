import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DirectoryWalker and Scan Engine Tests")
struct DirectoryWalkerTests {
    @Test("Symlink to large external directory does not inflate scanned size (§8 regression)")
    func symlinkToExternalDirDoesNotInflate() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let rootDir = tempBase.appendingPathComponent("scan_root")
        let externalDir = tempBase.appendingPathComponent("external_large")

        try FileManager.default.createDirectory(at: rootDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: externalDir, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let largeFile = externalDir.appendingPathComponent("large.bin")
        let largeData = Data(repeating: 0x55, count: 1024 * 1024)
        try largeData.write(to: largeFile)

        let symlink = rootDir.appendingPathComponent("link_to_external")
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: externalDir)

        let inodeSet = InodeSet()
        let result = DirectoryWalker.walk(url: rootDir, inodeSet: inodeSet)

        #expect(result.allocatedBytes < 100_000, "Symlink inflated root size to \(result.allocatedBytes) bytes")
        #expect(result.unreadableDirectoryCount == 0)
    }

    @Test("Hardlinks are deduplicated and counted only once")
    func hardlinkDeduplication() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let originalFile = tempBase.appendingPathComponent("original.bin")
        let data = Data(repeating: 0x42, count: 64 * 1024) // 64 KB
        try data.write(to: originalFile)

        let hardlinkFile = tempBase.appendingPathComponent("hardlink.bin")
        try FileManager.default.linkItem(at: originalFile, to: hardlinkFile)

        let inodeSet = InodeSet()
        let result = DirectoryWalker.walk(url: tempBase, inodeSet: inodeSet)

        #expect(result.allocatedBytes <= 80 * 1024)
    }

    @Test("A creation cutoff excludes entries born after it")
    func creationCutoffExcludesNewEntries() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        try Data(repeating: 0x41, count: 200_000).write(to: base.appendingPathComponent("old.bin"))
        let before = DirectoryWalker.walk(url: base, inodeSet: InodeSet()).allocatedBytes
        #expect(before > 0)

        let cutoff = Date()
        Thread.sleep(forTimeInterval: 0.02)

        let fresh = base.appendingPathComponent("Index.noindex", isDirectory: true)
        try FileManager.default.createDirectory(at: fresh, withIntermediateDirectories: true)
        try Data(repeating: 0x42, count: 300_000).write(to: fresh.appendingPathComponent("live.bin"))
        try Data(repeating: 0x43, count: 300_000).write(to: base.appendingPathComponent("new.bin"))

        let unfiltered = DirectoryWalker.walk(url: base, inodeSet: InodeSet()).allocatedBytes
        let surviving = DirectoryWalker
            .walk(url: base, inodeSet: InodeSet(), ignoringEntriesCreatedAfter: cutoff)
            .allocatedBytes

        #expect(unfiltered > before, "the fixture must actually add bytes")
        #expect(surviving == before, "only the pre-cutoff file may be counted")
    }

    @Test("A root born after the cutoff contributes nothing")
    func creationCutoffExcludesNewRoot() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let cutoff = Date()
        Thread.sleep(forTimeInterval: 0.02)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try Data(repeating: 0x41, count: 200_000).write(to: base.appendingPathComponent("new.bin"))

        #expect(DirectoryWalker.walk(url: base, inodeSet: InodeSet()).allocatedBytes > 0)
        #expect(
            DirectoryWalker
                .walk(url: base, inodeSet: InodeSet(), ignoringEntriesCreatedAfter: cutoff)
                .allocatedBytes == 0
        )
    }

    @Test("Atomic bundles are recognized correctly")
    func atomicBundles() {
        #expect(AtomicBundles.isAtomicBundle(URL(fileURLWithPath: "/path/App.app")))
        #expect(AtomicBundles.isAtomicBundle(URL(fileURLWithPath: "/path/Project.xcodeproj")))
        #expect(AtomicBundles.isAtomicBundle(URL(fileURLWithPath: "/path/Build.xcarchive")))
        #expect(AtomicBundles.isAtomicBundle(URL(fileURLWithPath: "/path/Workspace.xcworkspace")))
        #expect(!AtomicBundles.isAtomicBundle(URL(fileURLWithPath: "/path/folder")))
        #expect(!AtomicBundles.isAtomicBundle(URL(fileURLWithPath: "/path/file.txt")))
    }

    @Test("Volume capacity queries valid metrics")
    func volumeCapacity() {
        let capacity = VolumeCapacity.query()
        #expect(capacity.totalBytes > 0)
        #expect(capacity.freeBytes >= 0)
        #expect(capacity.purgeableBytes >= 0)
        #expect(capacity.usedBytes > 0)
    }
}
