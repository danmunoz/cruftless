import CruftlessCore
import Foundation
import Testing

@Suite("InventorySnapshot Tests")
struct InventorySnapshotTests {
    private let capacity = VolumeCapacity(
        totalBytes: 1_000_000,
        freeBytes: 400_000,
        purgeableBytes: 50_000,
        usedBytes: 550_000
    )

    private func inventory(entries: [InventoryEntry], scannedAt: Date = Date(timeIntervalSince1970: 1_000_000)) -> Inventory {
        Inventory(entries: entries, capacity: capacity, scannedAt: scannedAt, sizesAreUpperBound: true)
    }

    private func sizedEntry(
        _ location: TrackedLocation = LocationCatalog.derivedData,
        bytes: Int64 = 4_096,
        lastUsed: Date? = Date(timeIntervalSince1970: 900_000),
        roots: [RootSize] = [RootSize(url: URL(fileURLWithPath: "/tmp/derived"), allocatedBytes: 4_096)]
    ) -> InventoryEntry {
        .sized(
            location: location,
            reclaimableBytes: bytes,
            staleness: StalenessInfo(lastUsedDate: lastUsed),
            roots: roots
        )
    }

    @Test("A sized row round-trips with its size, staleness and roots")
    func roundTripsSizedRow() throws {
        let original = inventory(entries: [sizedEntry()])

        let restored = try #require(
            InventorySnapshot(original).inventory(capacity: capacity)
        )

        let entry = try #require(restored.entries.first)
        #expect(restored.entries.count == 1)
        #expect(entry.location.id == LocationCatalog.derivedData.id)
        #expect(entry.reclaimableBytes == 4_096)
        #expect(entry.staleness.lastUsedDate == Date(timeIntervalSince1970: 900_000))
        #expect(entry.roots.map(\.allocatedBytes) == [4_096])
        #expect(entry.rootURLs.map { $0.path(percentEncoded: false) } == ["/tmp/derived"])
        #expect(restored.scannedAt == original.scannedAt)
        #expect(restored.sizesAreUpperBound)
    }

    @Test("An unavailable row round-trips as unavailable, with its reason")
    func roundTripsUnavailableRow() throws {
        let original = inventory(entries: [
            .unavailable(location: LocationCatalog.simulatorRuntimes, reason: "simctl did not answer")
        ])

        let restored = try #require(InventorySnapshot(original).inventory(capacity: capacity))
        let entry = try #require(restored.entries.first)

        #expect(entry.isUnavailable)
        #expect(entry.unavailableReason == "simctl did not answer")
        #expect(entry.reclaimableBytes == 0)
    }

    @Test("A row whose location left the catalog is dropped, the rest survive")
    func dropsUnknownLocation() throws {
        let original = inventory(entries: [sizedEntry(), sizedEntry(LocationCatalog.archives, bytes: 8_192)])
        let catalog = [LocationCatalog.derivedData]

        let restored = try #require(
            InventorySnapshot(original).inventory(capacity: capacity, catalog: catalog)
        )

        #expect(restored.entries.map(\.id) == [LocationCatalog.derivedData.id])
    }

    @Test("A snapshot with no surviving row restores nothing")
    func dropsEverything() {
        let original = inventory(entries: [sizedEntry()])

        let restored = InventorySnapshot(original).inventory(
            capacity: capacity,
            catalog: [LocationCatalog.archives]
        )

        #expect(restored == nil)
    }

    @Test("A file from another schema version is ignored rather than migrated")
    func refusesForeignVersion() throws {
        let json = """
        {"version": 99, "scannedAt": "2026-01-01T00:00:00Z", "sizesAreUpperBound": true, "rows": []}
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let snapshot = try decoder.decode(InventorySnapshot.self, from: Data(json.utf8))

        #expect(snapshot.inventory(capacity: capacity) == nil)
    }

    @Test("Capacity comes from the caller, never from the snapshot")
    func capacityIsNeverPersisted() throws {
        let original = inventory(entries: [sizedEntry()])
        let live = VolumeCapacity(totalBytes: 9, freeBytes: 8, purgeableBytes: 7, usedBytes: 6)

        let restored = try #require(InventorySnapshot(original).inventory(capacity: live))

        #expect(restored.capacity == live)
    }
}
