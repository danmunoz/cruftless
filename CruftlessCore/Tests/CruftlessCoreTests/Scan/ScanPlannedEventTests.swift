import CruftlessCore
import Foundation
import Testing

@Suite("ScanEngine planned event")
struct ScanPlannedEventTests {
    private static func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-planned-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private static func makeRoot(under base: URL, named name: String) throws -> URL {
        let root = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: root.appendingPathComponent("payload.bin"))
        return root
    }

    private static func location(id: String, root: URL) -> TrackedLocation {
        TrackedLocation(
            id: id,
            title: id,
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: false,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [root] }
        )
    }

    private static func events(from stream: AsyncStream<ScanEvent>) async -> [ScanEvent] {
        var collected: [ScanEvent] = []
        for await event in stream { collected.append(event) }
        return collected
    }

    private static func plannedIds(in events: [ScanEvent]) -> [String]? {
        for event in events {
            if case let .planned(locations) = event { return locations.map(\.id) }
        }
        return nil
    }

    @Test("The plan arrives right after .started, before any row")
    func planArrivesEarly() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = [Self.location(id: "derivedData", root: try Self.makeRoot(under: base, named: "DerivedData"))]

        let events = await Self.events(from: await ScanEngine().scan(catalog: catalog))

        guard case .started = events.first else {
            Issue.record("expected .started first, got \(String(describing: events.first))")
            return
        }
        guard case .planned = events[1] else {
            Issue.record("expected .planned second, got \(events[1])")
            return
        }
    }

    @Test("Only locations with an existing root are promised")
    func skipsLocationsWithNoRoot() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = [
            Self.location(id: "derivedData", root: try Self.makeRoot(under: base, named: "DerivedData")),
            Self.location(id: "archives", root: base.appendingPathComponent("Nothing", isDirectory: true)),
            Self.location(id: "toolchains", root: try Self.makeRoot(under: base, named: "Toolchains"))
        ]

        let events = await Self.events(from: await ScanEngine().scan(catalog: catalog))

        #expect(Self.plannedIds(in: events) == ["derivedData", "toolchains"])
    }

    @Test("The plan keeps catalog order")
    func keepsCatalogOrder() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = [
            Self.location(id: "third", root: try Self.makeRoot(under: base, named: "C")),
            Self.location(id: "first", root: try Self.makeRoot(under: base, named: "A")),
            Self.location(id: "second", root: try Self.makeRoot(under: base, named: "B"))
        ]

        let events = await Self.events(from: await ScanEngine().scan(catalog: catalog))

        #expect(Self.plannedIds(in: events) == ["third", "first", "second"])
    }

    @Test("A partial rescan promises the subset it will walk")
    func rescanPromisesItsSubset() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = [
            Self.location(id: "derivedData", root: try Self.makeRoot(under: base, named: "DerivedData")),
            Self.location(id: "archives", root: try Self.makeRoot(under: base, named: "Archives"))
        ]

        let engine = ScanEngine()
        _ = await Self.events(from: await engine.scan(catalog: catalog))
        let rescan = await Self.events(from: await engine.rescan(locationIds: ["archives"], catalog: catalog))

        #expect(Self.plannedIds(in: rescan) == ["archives"])
    }

    @Test("Everything promised lands as a row")
    func everythingPromisedLands() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = [
            Self.location(id: "derivedData", root: try Self.makeRoot(under: base, named: "DerivedData")),
            Self.location(id: "toolchains", root: try Self.makeRoot(under: base, named: "Toolchains"))
        ]

        let events = await Self.events(from: await ScanEngine().scan(catalog: catalog))
        let promised = Set(try #require(Self.plannedIds(in: events)))
        let landed = Set(events.compactMap { event -> String? in
            if case let .locationScanned(entry) = event { return entry.id }
            return nil
        })

        #expect(promised == landed)
    }
}
