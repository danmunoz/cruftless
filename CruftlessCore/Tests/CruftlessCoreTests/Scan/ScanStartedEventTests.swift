import CruftlessCore
import Foundation
import Testing

@Suite("ScanEngine started event")
struct ScanStartedEventTests {
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

    @Test("A location starts only once the walk queue reaches its walk")
    func startsWaitForTheWalkQueue() async throws {
        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(under: base, names: ["alpha", "beta", "gamma"], files: 4)

        let hold = WalkQueueHold()
        var heldEvents: [String] = []
        var order: [String] = []
        for await event in await ScanEngine().scan(catalog: catalog) {
            switch event {
            case .planned:
                // Gives a start announced outside the walk queue time to show up while the queue is still held.
                Task {
                    try? await Task.sleep(for: .milliseconds(200))
                    hold.release()
                }
            case let .locationStarted(locationId):
                if hold.isHeld { heldEvents.append("started \(locationId)") }
                order.append("started \(locationId)")
            case let .locationScanned(entry):
                if hold.isHeld { heldEvents.append("scanned \(entry.location.id)") }
                order.append("scanned \(entry.location.id)")
            default:
                break
            }
        }
        hold.release()

        #expect(!hold.releasedByFailsafe, "the scan never planned, so the walk queue was never released")
        #expect(heldEvents.isEmpty, "reported while the walk queue was held: \(heldEvents)")
        for location in catalog {
            let started = try #require(order.firstIndex(of: "started \(location.id)"), "\(location.id) never started")
            let scanned = try #require(order.firstIndex(of: "scanned \(location.id)"), "\(location.id) never landed")
            #expect(started < scanned, "\(location.id) landed before it started")
        }
    }
}
