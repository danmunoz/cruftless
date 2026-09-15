import CruftlessCore
import Foundation
import Testing

@Suite("ScanEngine started event")
struct ScanStartedEventTests {
    private static let filesPerRoot = 2000

    private static func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-started-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
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

    private static func makeCatalog(under base: URL, names: [String], files: Int) throws -> [TrackedLocation] {
        try names.map { name in
            let root = base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for index in 0 ..< files {
                try Data(repeating: 0x41, count: 64).write(to: root.appendingPathComponent("f\(index)"))
            }
            return location(id: name, root: root)
        }
    }

    @Test("A location starts before it lands, and every promised one starts")
    func startPrecedesItsRow() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(under: base, names: ["alpha", "beta"], files: 4)

        var startedAt: [String: Int] = [:]
        var scannedAt: [String: Int] = [:]
        var index = 0
        for await event in await ScanEngine().scan(catalog: catalog) {
            switch event {
            case let .locationStarted(locationId):
                #expect(startedAt[locationId] == nil, "\(locationId) started twice")
                startedAt[locationId] = index
            case let .locationScanned(entry):
                scannedAt[entry.location.id] = index
            default:
                break
            }
            index += 1
        }

        for location in catalog {
            let started = try #require(startedAt[location.id], "\(location.id) never started")
            let scanned = try #require(scannedAt[location.id], "\(location.id) never landed")
            #expect(started < scanned, "\(location.id) landed before it started")
        }
    }

    @Test("Locations start one at a time, as the walk queue reaches them")
    func startsAreSpreadAcrossTheScan() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(
            under: base,
            names: ["alpha", "beta", "gamma"],
            files: Self.filesPerRoot
        )

        let start = Date()
        var startTimes: [TimeInterval] = []
        var inFlight: Set<String> = []
        var peakInFlight = 0
        for await event in await ScanEngine().scan(catalog: catalog) {
            switch event {
            case let .locationStarted(locationId):
                startTimes.append(Date().timeIntervalSince(start))
                inFlight.insert(locationId)
                peakInFlight = max(peakInFlight, inFlight.count)
            case let .locationScanned(entry):
                inFlight.remove(entry.location.id)
            default:
                break
            }
        }

        #expect(startTimes.count == catalog.count)
        let spread = (startTimes.last ?? 0) - (startTimes.first ?? 0)
        #expect(
            spread > 0.003,
            "every location started within \(Int(spread * 1000))ms of the first: they are being announced in one burst"
        )
        #expect(
            peakInFlight <= 2,
            "\(peakInFlight) of \(catalog.count) locations were measuring at once; the walk queue is serial"
        )
    }
}
