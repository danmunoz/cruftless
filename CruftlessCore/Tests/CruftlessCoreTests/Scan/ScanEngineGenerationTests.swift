import CruftlessCore
import Foundation
import Testing

@Suite("ScanEngine generations")
struct ScanEngineGenerationTests {
    private static func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-generation-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func makeCatalog(under base: URL, names: [String]) throws -> [TrackedLocation] {
        try names.map { name in
            let root = base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 4096).write(to: root.appendingPathComponent("payload.bin"))
            return TrackedLocation(
                id: name,
                title: name,
                icon: .symbol("folder"),
                tier: .regen,
                hasDrillDown: true,
                stalenessSource: .newestChildMtime,
                resolveRoots: { [root] }
            )
        }
    }

    @Test("Walks still queued when a newer generation arrives never run")
    func supersededWalksAreSkipped() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(under: base, names: ["a", "b", "c", "d"])
        let engine = ScanEngine()

        // Holds the walk queue so every walk of this scan is still waiting when the new generation lands.
        let release = DispatchSemaphore(value: 0)
        ScanEngine.walkQueue.async { release.wait() }

        var released = false
        var started = 0
        var scanned = 0
        var completed = false
        for await event in await engine.scan(catalog: catalog, generation: 1) {
            switch event {
            case .planned:
                await engine.invalidate(generation: 2)
                release.signal()
                released = true
            case .locationStarted:
                started += 1
            case .locationScanned:
                scanned += 1
            case .completed:
                completed = true
            default:
                break
            }
        }
        if !released { release.signal() }

        #expect(released)
        #expect(started == 0)
        #expect(scanned == 0)
        #expect(!completed)
    }

    @Test("Invalidating with the generation already running keeps that scan's measurements")
    func sameGenerationInvalidateKeepsRunningScan() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(under: base, names: ["derivedData"])
        let engine = ScanEngine()

        for await event in await engine.scan(catalog: catalog, generation: 1) {
            if case .locationScanned = event {
                await engine.invalidate(generation: 1)
            }
        }

        #expect(await engine.childSizes(for: "derivedData")["payload.bin"] != nil)
        #expect(await engine.cachedInventory() != nil)
    }

    @Test("A rescan from a newer generation walks everything instead of merging into the older inventory")
    func newerGenerationRescanStartsFresh() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(under: base, names: ["a", "b"])
        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: catalog, generation: 1) {}

        var planned: Set<String> = []
        for await event in await engine.rescan(locationIds: ["a"], catalog: catalog, generation: 2) {
            if case let .planned(locations) = event { planned = Set(locations.map(\.id)) }
        }

        #expect(planned == ["a", "b"])
    }
}
