import CruftlessCore
import Foundation
import Testing

@Suite("Unreadable directories are counted and reported")
struct UnreadableDirectoryTests {
    private static func makeTree() throws -> (base: URL, locked: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let readable = base.appendingPathComponent("readable", isDirectory: true)
        let locked = base.appendingPathComponent("locked", isDirectory: true)

        try FileManager.default.createDirectory(at: readable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: locked, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 8192).write(to: readable.appendingPathComponent("payload.bin"))
        try Data(repeating: 0x42, count: 8192).write(to: locked.appendingPathComponent("hidden.bin"))

        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: locked.path)
        return (base, locked)
    }

    private static func cleanUp(base: URL, locked: URL) {
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: locked.path)
        TestFileSystem.removeDirectoryRecursively(at: base)
    }

    @Test("The walker counts an unopenable directory and remembers the first one")
    func walkerCountsUnreadableDirectory() throws {
        let tree = try Self.makeTree()
        defer { Self.cleanUp(base: tree.base, locked: tree.locked) }

        let result = DirectoryWalker.walk(url: tree.base, inodeSet: InodeSet())

        #expect(result.unreadableDirectoryCount == 1)
        #expect(result.firstUnreadablePath?.hasSuffix("/locked") == true)
        #expect(result.allocatedBytes > 0)
    }

    @Test("Per-child breakdown carries the unreadable count up to the root total")
    func breakdownCarriesUnreadableCount() throws {
        let tree = try Self.makeTree()
        defer { Self.cleanUp(base: tree.base, locked: tree.locked) }

        let breakdown = DirectoryWalker.walkWithChildren(url: tree.base, inodeSet: InodeSet())
        let basePath = ProtectedPaths.normalize(tree.base)

        #expect(breakdown.total.unreadableDirectoryCount == 1)
        #expect(breakdown.sizes["\(basePath)/locked"]?.unreadableDirectoryCount == 1)
        #expect(breakdown.sizes["\(basePath)/readable"]?.unreadableDirectoryCount == 0)
    }

    @Test("A root that cannot be opened at all is reported, not silently zero")
    func unopenableRootIsReported() throws {
        let tree = try Self.makeTree()
        defer { Self.cleanUp(base: tree.base, locked: tree.locked) }

        let breakdown = DirectoryWalker.walkWithChildren(url: tree.locked, inodeSet: InodeSet())

        #expect(breakdown.total.unreadableDirectoryCount == 1)
        #expect(breakdown.total.allocatedBytes == 0)
    }

    @Test("The scan emits .failed after the row, so the partial size still shows")
    func scanEmitsFailedAfterTheEntry() async throws {
        let tree = try Self.makeTree()
        defer { Self.cleanUp(base: tree.base, locked: tree.locked) }

        let location = TrackedLocation(
            id: "unreadableTest",
            title: "Unreadable Test",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: false,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [tree.base] }
        )

        var sawEntry = false
        var failureReason: String?
        var failureCameAfterEntry = false

        for await event in await ScanEngine().scan(catalog: [location]) {
            switch event {
            case let .locationScanned(entry):
                #expect(entry.location.id == "unreadableTest")
                #expect(entry.reclaimableBytes > 0)
                sawEntry = true
            case let .failed(locationId, reason):
                #expect(locationId == "unreadableTest")
                failureReason = reason
                failureCameAfterEntry = sawEntry
            default:
                break
            }
        }

        #expect(sawEntry)
        #expect(failureCameAfterEntry)
        let reason = try #require(failureReason)
        #expect(reason.contains("1 folder could not be read"))
        #expect(reason.contains("sizes are incomplete"))
        #expect(reason.contains("locked"))
    }

    @Test("A fully readable location emits no failure")
    func readableLocationEmitsNoFailure() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try Data(repeating: 0x43, count: 4096).write(to: base.appendingPathComponent("payload.bin"))

        let location = TrackedLocation(
            id: "readableTest",
            title: "Readable Test",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: false,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [base] }
        )

        var failures = 0
        for await event in await ScanEngine().scan(catalog: [location]) {
            if case .failed = event { failures += 1 }
        }

        #expect(failures == 0)
    }
}
