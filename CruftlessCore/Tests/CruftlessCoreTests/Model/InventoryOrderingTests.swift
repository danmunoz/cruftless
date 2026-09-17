import CruftlessCore
import Foundation
import Testing

@Suite("Inventory display ordering")
struct InventoryOrderingTests {
    private let capacity = VolumeCapacity(
        totalBytes: 1_000_000, freeBytes: 500_000, purgeableBytes: 10000, usedBytes: 490_000
    )

    private func inventory(_ entries: [InventoryEntry]) -> Inventory {
        Inventory(entries: entries, capacity: capacity, scannedAt: Date(timeIntervalSince1970: 1), sizesAreUpperBound: true)
    }

    private func sized(_ location: TrackedLocation, bytes: Int64) -> InventoryEntry {
        .sized(location: location, reclaimableBytes: bytes, staleness: StalenessInfo(lastUsedDate: nil), roots: [])
    }

    @Test("Equal sizes keep catalog order, so rows never shuffle between rescans")
    func equalSizesKeepCatalogOrder() {
        let entries = [
            sized(LocationCatalog.codingAssistant, bytes: 0),
            sized(LocationCatalog.derivedData, bytes: 0),
            sized(LocationCatalog.deviceSupport, bytes: 0)
        ]
        let ordered = inventory(entries).entries.map(\.id)
        #expect(ordered == [
            LocationCatalog.deviceSupport.id, LocationCatalog.derivedData.id, LocationCatalog.codingAssistant.id
        ])
    }

    @Test("Locations outside the catalog tie-break by title, then id")
    func foreignLocationsBreakTies() {
        let beta = TrackedLocation(
            id: "b-id", title: "Beta", icon: .symbol("folder"), tier: .regen,
            hasDrillDown: false, stalenessSource: .topLevelMtime, resolveRoots: { [] }
        )
        let alpha = TrackedLocation(
            id: "a-id", title: "Alpha", icon: .symbol("folder"), tier: .regen,
            hasDrillDown: false, stalenessSource: .topLevelMtime, resolveRoots: { [] }
        )
        let ordered = inventory([sized(beta, bytes: 0), sized(alpha, bytes: 0)]).entries.map(\.id)
        #expect(ordered == ["a-id", "b-id"])
    }

    @Test("Sized rows are only the entries above 0 B")
    func sizedRowsAreNonzeroOnly() {
        let inv = inventory([
            sized(LocationCatalog.derivedData, bytes: 100),
            sized(LocationCatalog.ibSupport, bytes: 0),
            .unavailable(location: LocationCatalog.toolchains, reason: "permission denied")
        ])
        #expect(inv.sizedRows.map(\.id) == [LocationCatalog.derivedData.id])
    }

    @Test("Zero-byte rows come before unavailable rows below the separator")
    func zeroBeforeUnavailable() {
        let inv = inventory([
            .unavailable(location: LocationCatalog.toolchains, reason: "permission denied"),
            sized(LocationCatalog.ibSupport, bytes: 0),
            sized(LocationCatalog.swiftPMCache, bytes: 0),
            .unavailable(location: LocationCatalog.simulatorRuntimes, reason: "simctl did not answer")
        ])
        #expect(inv.zeroOrUnavailableRows.map(\.id) == [
            LocationCatalog.swiftPMCache.id, LocationCatalog.ibSupport.id,
            LocationCatalog.simulatorRuntimes.id, LocationCatalog.toolchains.id
        ])
    }

    @Test("The partitions together cover exactly the entries, none dropped or repeated")
    func partitionsCoverEverything() {
        let entries = [
            sized(LocationCatalog.derivedData, bytes: 300),
            sized(LocationCatalog.archives, bytes: 100),
            sized(LocationCatalog.ibSupport, bytes: 0),
            .unavailable(location: LocationCatalog.toolchains, reason: "permission denied")
        ]
        let inv = inventory(entries)
        let combined = (inv.sizedRows + inv.zeroOrUnavailableRows).map(\.id)
        #expect(Set(combined) == Set(inv.entries.map(\.id)))
        #expect(combined.count == inv.entries.count)
    }

    @Test("Two inventories built from the same rows order identically")
    func orderingIsDeterministic() {
        let entries = [
            sized(LocationCatalog.swiftPMCache, bytes: 0),
            sized(LocationCatalog.ibSupport, bytes: 0),
            sized(LocationCatalog.derivedData, bytes: 0),
            .unavailable(location: LocationCatalog.toolchains, reason: "permission denied")
        ]
        #expect(inventory(entries).entries == inventory(Array(entries.reversed())).entries)
    }
}
