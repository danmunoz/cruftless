import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("Scan Child Breakdown Tests")
struct ChildBreakdownTests {
    private func makeTree() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)

        for (name, size) in [("ProjectA", 8192), ("ProjectB", 4096)] {
            let dir = base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let payload = Data(repeating: 0x41, count: size)
            try payload.write(to: dir.appendingPathComponent("payload.bin"))
        }
        return base
    }

    @Test("Per-child sizes sum to the root total")
    func childrenSumToTotal() throws {
        let base = try makeTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let breakdown = DirectoryWalker.walkWithChildren(url: base, inodeSet: InodeSet())
        let summed = breakdown.sizes.values.reduce(Int64(0)) { $0 + $1.allocatedBytes }

        #expect(breakdown.sizes.count == 2)
        #expect(summed == breakdown.total.allocatedBytes)
        #expect(breakdown.total.allocatedBytes > 0)
    }

    @Test("The breakdown total matches a plain walk of the same root")
    func breakdownMatchesPlainWalk() throws {
        let base = try makeTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let plain = DirectoryWalker.walk(url: base, inodeSet: InodeSet())
        let breakdown = DirectoryWalker.walkWithChildren(url: base, inodeSet: InodeSet())

        #expect(plain.allocatedBytes == breakdown.total.allocatedBytes)
        #expect(plain.newestMtime == breakdown.total.newestMtime)
    }

    @Test("A bundle root is not split into its contents")
    func bundleRootIsAtomic() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundle = base.appendingPathComponent("Xcode.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try Data(repeating: 0x42, count: 4096).write(to: contents.appendingPathComponent("MacOS.bin"))

        let breakdown = DirectoryWalker.walkWithChildren(url: bundle, inodeSet: InodeSet())

        #expect(breakdown.sizes.count == 1)
        #expect(breakdown.sizes[ProtectedPaths.normalize(bundle)]?.allocatedBytes == breakdown.total.allocatedBytes)
        #expect(breakdown.total.allocatedBytes > 0)
    }

    @Test("A scan populates per-child sizes for its locations")
    func scanPopulatesChildSizes() async throws {
        let base = try makeTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let location = TrackedLocation(
            id: "testLocation",
            title: "Test",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [base] }
        )

        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: [location]) {}

        let sizes = await engine.childSizes(for: "testLocation")
        #expect(sizes.count == 2)
        #expect(sizes["ProjectA"] ?? 0 > 0)
        #expect(sizes["ProjectB"] ?? 0 > 0)

        let children = await engine.children(of: "testLocation", catalog: [location])
        #expect(children.count == 2)
        #expect(children.map(\.reclaimableBytes).allSatisfy { $0 > 0 })

        for child in children {
            #expect(child.reclaimableBytes == sizes[child.name])
        }
    }

    @Test("Invalidating the engine clears cached child sizes")
    func invalidateClearsChildSizes() async throws {
        let base = try makeTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let location = TrackedLocation(
            id: "testLocation",
            title: "Test",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [base] }
        )

        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: [location]) {}
        #expect(await !engine.childSizes(for: "testLocation").isEmpty)

        await engine.invalidate()
        #expect(await engine.childSizes(for: "testLocation").isEmpty)
    }

    @Test("A bundle root drills down to the bundle, not its contents")
    func bundleRootDrillsDownToItself() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let bundle = base.appendingPathComponent("Xcode.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        try Data(repeating: 0x43, count: 2048).write(to: contents.appendingPathComponent("bin"))

        let location = TrackedLocation(
            id: "xcodeInstalls",
            title: "Xcode installs",
            icon: .symbol("hammer"),
            tier: .reveal,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [bundle] }
        )

        let children = DrillDownProvider.loadChildren(for: location)

        #expect(children.count == 1)
        #expect(children[0].name == "Xcode.app")
        #expect(children[0].reclaimableBytes > 0)
    }
}

@Suite("Deeper size recording")
struct DeeperRecordingTests {
    private struct ArchiveTree {
        let root: URL
        let dateFolder: URL
        let archives: [URL]
    }

    private func makeArchiveTree() throws -> ArchiveTree {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let dateFolder = root.appendingPathComponent("2026-09-06", isDirectory: true)
        try FileManager.default.createDirectory(at: dateFolder, withIntermediateDirectories: true)

        var made: [URL] = []
        for (name, bytes) in [("First.xcarchive", 40_000), ("Second.xcarchive", 20_000)] {
            let archive = dateFolder.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: bytes)
                .write(to: archive.appendingPathComponent("payload.bin"))
            made.append(archive)
        }

        return ArchiveTree(root: root, dateFolder: dateFolder, archives: made)
    }

    @Test("Depth 2 records the archives as well as the date folder holding them")
    func depthTwoRecordsArchives() throws {
        let tree = try makeArchiveTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: tree.root) }

        let breakdown = DirectoryWalker.walkWithChildren(
            url: tree.root,
            inodeSet: InodeSet(),
            recordingDepth: 2
        )

        #expect(breakdown.sizes[ProtectedPaths.normalize(tree.dateFolder)] != nil)
        for archive in tree.archives {
            #expect(breakdown.sizes[ProtectedPaths.normalize(archive)] != nil, "\(archive.lastPathComponent)")
        }
    }

    @Test("Recording depth does not change the total")
    func depthDoesNotChangeTotal() throws {
        let tree = try makeArchiveTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: tree.root) }

        let shallow = DirectoryWalker.walkWithChildren(url: tree.root, inodeSet: InodeSet())
        let deep = DirectoryWalker.walkWithChildren(
            url: tree.root,
            inodeSet: InodeSet(),
            recordingDepth: 2
        )

        #expect(shallow.total.allocatedBytes == deep.total.allocatedBytes)
        #expect(shallow.total.newestMtime == deep.total.newestMtime)
    }

    @Test("childSizes reports immediate children only, never the deeper entries")
    func childSizesExcludesDeeperEntries() async throws {
        let tree = try makeArchiveTree()
        defer { TestFileSystem.removeDirectoryRecursively(at: tree.root) }

        let archives = TrackedLocation(
            id: "archives",
            title: "Archives",
            icon: .symbol("folder"),
            tier: .irreversible,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [tree.root] }
        )

        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: [archives]) {}

        let sizes = await engine.childSizes(for: "archives")
        #expect(sizes.keys.sorted() == ["2026-09-06"])
        #expect(sizes["First.xcarchive"] == nil)
    }
}
