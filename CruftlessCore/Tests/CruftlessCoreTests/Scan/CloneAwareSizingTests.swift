@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("Clone-aware sizing")
struct CloneAwareSizingTests {
    private static let payloadSize = 1024 * 1024

    @Test("Bulk entries agree with lstat on type, identity, links, size and dates")
    func bulkEntriesAgreeWithLstat() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try FileManager.default.createDirectory(at: base.appendingPathComponent("folder"), withIntermediateDirectories: true)
        try writePayload(to: base.appendingPathComponent("file.bin"))
        try FileManager.default.linkItem(at: base.appendingPathComponent("file.bin"), to: base.appendingPathComponent("hardlink.bin"))
        try FileManager.default.createSymbolicLink(atPath: base.appendingPathComponent("link").path, withDestinationPath: "file.bin")
        #expect(mkfifo(base.appendingPathComponent("fifo").path, mode_t(0o600)) == 0)

        var entries: [WalkEntry] = []
        #expect(DirectoryEntryReader.forEachEntry(inDirectory: base.path) { entries.append($0) })
        #expect(Set(entries.map(\.name)) == ["folder", "file.bin", "hardlink.bin", "link", "fifo"])

        for entry in entries {
            var info = stat()
            #expect(lstat(base.appendingPathComponent(entry.name).path, &info) == 0)
            #expect(entry.device == info.st_dev, "\(entry.name)")
            #expect(entry.inode == info.st_ino, "\(entry.name)")
            #expect(entry.kind == expectedKind(info.st_mode), "\(entry.name)")
            #expect(entry.modificationDate.timeIntervalSince1970 == seconds(info.st_mtimespec), "\(entry.name)")
            #expect(entry.creationDate.timeIntervalSince1970 == seconds(info.st_birthtimespec), "\(entry.name)")
            if entry.kind != .directory {
                #expect(entry.linkCount == UInt32(info.st_nlink), "\(entry.name)")
                #expect(entry.allocatedBytes == Int64(info.st_blocks) * 512, "\(entry.name)")
            }
            #expect(!entry.isMountPoint)
        }
    }

    @Test("A file read on its own matches the same file read in bulk")
    func singleEntryMatchesBulk() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try writePayload(to: base.appendingPathComponent("file.bin"))

        var bulk: WalkEntry?
        _ = DirectoryEntryReader.forEachEntry(inDirectory: base.path) { bulk = $0 }
        let single = try #require(DirectoryEntryReader.entry(atPath: base.appendingPathComponent("file.bin").path))
        let listed = try #require(bulk)
        #expect(single.name == listed.name)
        #expect(single.inode == listed.inode)
        #expect(single.allocatedBytes == listed.allocatedBytes)
        #expect(single.exclusiveBytes == listed.exclusiveBytes)
    }

    @Test("A clone pair inside the tree counts its shared blocks once")
    func clonePairInsideTreeCountsOnce() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let original = base.appendingPathComponent("original.bin")
        try writePayload(to: original)
        try cloneFile(original, to: base.appendingPathComponent("clone.bin"))
        let single = try allocatedSize(of: original)

        let result = DirectoryWalker.walk(url: base, inodeSet: InodeSet())

        #expect(result.allocatedBytes == single * 2)
        #expect(result.exclusiveBytes == single)
    }

    @Test("A clone whose source is outside the tree frees nothing of the shared blocks")
    func cloneOfOutsideFileIsNotExclusive() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let inside = base.appendingPathComponent("inside", isDirectory: true)
        try FileManager.default.createDirectory(at: inside, withIntermediateDirectories: true)
        let original = base.appendingPathComponent("original.bin")
        try writePayload(to: original)
        try cloneFile(original, to: inside.appendingPathComponent("clone.bin"))

        let result = DirectoryWalker.walk(url: inside, inodeSet: InodeSet())

        #expect(result.allocatedBytes == (try allocatedSize(of: original)))
        #expect(result.exclusiveBytes == 0)
    }

    @Test("A clone family split across two rows is exclusive to neither row but to their parent")
    func cloneFamilySplitAcrossChildren() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let first = base.appendingPathComponent("First", isDirectory: true)
        let second = base.appendingPathComponent("Second", isDirectory: true)
        try FileManager.default.createDirectory(at: first, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: second, withIntermediateDirectories: true)
        let original = first.appendingPathComponent("original.bin")
        try writePayload(to: original)
        try cloneFile(original, to: second.appendingPathComponent("clone.bin"))
        let single = try allocatedSize(of: original)

        let breakdown = DirectoryWalker.walkWithChildren(url: base, inodeSet: InodeSet())

        #expect(breakdown.total.allocatedBytes == single * 2)
        #expect(breakdown.total.exclusiveBytes == single)
        #expect(breakdown.sizes[ProtectedPaths.normalize(first)]?.exclusiveBytes == 0)
        #expect(breakdown.sizes[ProtectedPaths.normalize(second)]?.exclusiveBytes == 0)
    }

    @Test("A file without clones is exclusive in full")
    func plainFileIsFullyExclusive() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try writePayload(to: base.appendingPathComponent("plain.bin"))

        let result = DirectoryWalker.walk(url: base, inodeSet: InodeSet())

        #expect(result.allocatedBytes > 0)
        #expect(result.exclusiveBytes == result.allocatedBytes)
    }

    @Test("A mounted volume below a directory is reported as foreign")
    func mountPointIsForeign() throws {
        var entries: [String: WalkEntry] = [:]
        _ = DirectoryEntryReader.forEachEntry(inDirectory: "/System/Volumes") { entries[$0.name] = $0 }
        let data = try #require(entries["Data"])
        let parent = try #require(DirectoryEntryReader.entry(atPath: "/System/Volumes"))

        #expect(data.isMountPoint || data.device != parent.device)
    }

    private func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return URL(fileURLWithPath: ProtectedPaths.normalize(base), isDirectory: true)
    }

    private func writePayload(to url: URL) throws {
        var generator = SystemRandomNumberGenerator()
        let bytes = (0 ..< Self.payloadSize / 8).flatMap { _ in withUnsafeBytes(of: generator.next() as UInt64) { Array($0) } }
        try Data(bytes).write(to: url)
    }

    private func cloneFile(_ source: URL, to destination: URL) throws {
        let status = clonefile(source.path, destination.path, 0)
        try #require(status == 0, "clonefile failed: \(String(cString: strerror(errno)))")
    }

    private func allocatedSize(of url: URL) throws -> Int64 {
        var info = stat()
        try #require(lstat(url.path, &info) == 0)
        return Int64(info.st_blocks) * 512
    }

    private func expectedKind(_ mode: mode_t) -> WalkEntry.Kind {
        switch mode & S_IFMT {
        case S_IFDIR: .directory
        case S_IFREG: .regular
        case S_IFLNK: .symlink
        default: .other
        }
    }

    private func seconds(_ value: timespec) -> TimeInterval {
        TimeInterval(value.tv_sec) + TimeInterval(value.tv_nsec) / 1_000_000_000
    }
}
