import CruftlessCore
import Foundation
import Testing

@Suite("ScanEngine partial rescan")
struct ScanEnginePartialRescanTests {
    private static func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-rescan-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func makeRoot(under base: URL, named name: String, payloadBytes: Int) throws -> URL {
        let root = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: payloadBytes).write(to: root.appendingPathComponent("payload.bin"))
        return root
    }

    private static func location(id: String, root: URL) -> TrackedLocation {
        TrackedLocation(
            id: id,
            title: id,
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .newestChildMtime,
            resolveRoots: { [root] }
        )
    }

    private static func inventory(from stream: AsyncStream<ScanEvent>) async -> Inventory? {
        var latest: Inventory?
        for await event in stream {
            if case let .completed(inventory) = event { latest = inventory }
        }
        return latest
    }

    @Test("A rescan replaces only its own entry and leaves the others intact")
    func rescanReplacesOnlyItsOwnEntry() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let derivedRoot = try Self.makeRoot(under: base, named: "DerivedData", payloadBytes: 4096)
        let archivesRoot = try Self.makeRoot(under: base, named: "Archives", payloadBytes: 8192)
        let catalog = [
            Self.location(id: "derivedData", root: derivedRoot),
            Self.location(id: "archives", root: archivesRoot)
        ]

        let engine = ScanEngine()
        let full = await Self.inventory(from: await engine.scan(catalog: catalog))
        let archivesBefore = try #require(full?.entries.first { $0.id == "archives" }?.reclaimableBytes)
        let derivedBefore = try #require(full?.entries.first { $0.id == "derivedData" }?.reclaimableBytes)

        try Data(repeating: 0x42, count: 65536).write(to: derivedRoot.appendingPathComponent("more.bin"))
        TestFileSystem.removeFile(at: archivesRoot.appendingPathComponent("payload.bin"))

        let merged = try #require(
            await Self.inventory(from: await engine.rescan(locationIds: ["derivedData"], catalog: catalog))
        )

        #expect(merged.entries.count == 2)
        #expect(merged.entries.first { $0.id == "archives" }?.reclaimableBytes == archivesBefore)
        let derivedAfter = try #require(merged.entries.first { $0.id == "derivedData" }?.reclaimableBytes)
        #expect(derivedAfter > derivedBefore)
    }

    @Test("A rescanned location whose root has vanished loses its row")
    func vanishedRootDropsItsRow() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let derivedRoot = try Self.makeRoot(under: base, named: "DerivedData", payloadBytes: 4096)
        let archivesRoot = try Self.makeRoot(under: base, named: "Archives", payloadBytes: 8192)
        let catalog = [
            Self.location(id: "derivedData", root: derivedRoot),
            Self.location(id: "archives", root: archivesRoot)
        ]

        let engine = ScanEngine()
        _ = await Self.inventory(from: await engine.scan(catalog: catalog))

        TestFileSystem.removeDirectoryRecursively(at: derivedRoot)

        let merged = try #require(
            await Self.inventory(from: await engine.rescan(locationIds: ["derivedData"], catalog: catalog))
        )

        #expect(merged.entries.map(\.id) == ["archives"])
    }

    @Test("A rescan before any full scan falls back to scanning everything")
    func rescanWithoutACacheScansEverything() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let catalog = [
            Self.location(id: "derivedData", root: try Self.makeRoot(under: base, named: "DerivedData", payloadBytes: 4096)),
            Self.location(id: "archives", root: try Self.makeRoot(under: base, named: "Archives", payloadBytes: 8192))
        ]

        let engine = ScanEngine()
        let inventory = try #require(
            await Self.inventory(from: await engine.rescan(locationIds: ["derivedData"], catalog: catalog))
        )

        #expect(Set(inventory.entries.map(\.id)) == ["derivedData", "archives"])
    }

    @Test("A rescan leaves another location's cached child sizes alone")
    func rescanKeepsOtherChildSizes() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let derivedRoot = try Self.makeRoot(under: base, named: "DerivedData", payloadBytes: 4096)
        let archivesRoot = try Self.makeRoot(under: base, named: "Archives", payloadBytes: 8192)
        try FileManager.default.createDirectory(
            at: archivesRoot.appendingPathComponent("2026-09-07", isDirectory: true),
            withIntermediateDirectories: true
        )
        let catalog = [
            Self.location(id: "derivedData", root: derivedRoot),
            Self.location(id: "archives", root: archivesRoot)
        ]

        let engine = ScanEngine()
        _ = await Self.inventory(from: await engine.scan(catalog: catalog))
        let archiveChildrenBefore = await engine.childSizes(for: "archives")
        #expect(!archiveChildrenBefore.isEmpty)

        _ = await Self.inventory(from: await engine.rescan(locationIds: ["derivedData"], catalog: catalog))

        #expect(await engine.childSizes(for: "archives") == archiveChildrenBefore)
        #expect(!(await engine.childSizes(for: "derivedData").isEmpty))
    }

    @Test("A rescan of an unknown location changes nothing")
    func unknownLocationIsANoOp() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let catalog = [Self.location(id: "derivedData", root: try Self.makeRoot(under: base, named: "DerivedData", payloadBytes: 4096))]
        let engine = ScanEngine()
        let full = try #require(await Self.inventory(from: await engine.scan(catalog: catalog)))

        var events: [ScanEvent] = []
        for await event in await engine.rescan(locationIds: ["nope"], catalog: catalog) {
            events.append(event)
        }

        #expect(events.isEmpty)
        #expect(await engine.cachedInventory()?.entries.map(\.id) == full.entries.map(\.id))
    }
}
