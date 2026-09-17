import CruftlessCore
import Foundation
import Testing

@Suite("ScanProgress Tests")
struct ScanProgressTests {
    private func entry(_ location: TrackedLocation, bytes: Int64) -> InventoryEntry {
        .sized(
            location: location,
            reclaimableBytes: bytes,
            staleness: StalenessInfo(lastUsedDate: nil),
            roots: []
        )
    }

    @Test("Nothing is drawn until the scan says what it will cover")
    func hasPlan() {
        var progress = ScanProgress()
        #expect(!progress.hasPlan)

        progress.plan([LocationCatalog.derivedData])

        #expect(progress.hasPlan)
        #expect(progress.plannedCount == 1)
        #expect(progress.completedCount == 0)
    }

    @Test("A landed row leaves the pending list, which keeps catalog order")
    func pendingKeepsOrder() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData, LocationCatalog.archives, LocationCatalog.toolchains])

        progress.record(entry(LocationCatalog.archives, bytes: 10))

        #expect(progress.pending.map(\.id) == [LocationCatalog.derivedData.id, LocationCatalog.toolchains.id])
        #expect(progress.completedCount == 1)
    }

    @Test("Rows are ordered largest first, as the finished list orders them")
    func rowsSortedBySize() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData, LocationCatalog.archives])
        progress.record(entry(LocationCatalog.derivedData, bytes: 10))
        progress.record(entry(LocationCatalog.archives, bytes: 500))

        #expect(progress.rows.map(\.id) == [LocationCatalog.archives.id, LocationCatalog.derivedData.id])
    }

    @Test("Measured rows tie-break exactly as the finished list does")
    func rowsTieBreakLikeInventory() {
        var progress = ScanProgress()
        progress.plan(LocationCatalog.all)
        progress.record(entry(LocationCatalog.swiftPMCache, bytes: 0))
        progress.record(entry(LocationCatalog.ibSupport, bytes: 0))
        #expect(progress.rows.map(\.id) == [LocationCatalog.swiftPMCache.id, LocationCatalog.ibSupport.id])
    }

    @Test("The running total counts deletable tiers only")
    func totalCountsDeletableTiersOnly() {
        var progress = ScanProgress()
        progress.plan(LocationCatalog.all)
        progress.record(entry(LocationCatalog.derivedData, bytes: 100))
        progress.record(entry(LocationCatalog.xcodeInstalls, bytes: 90000))
        progress.record(entry(LocationCatalog.simulatorDyldCache, bytes: 80000))

        #expect(progress.reclaimableBytes == 100)
    }

    @Test("An unavailable row counts as landed but adds nothing")
    func unavailableRowAddsNothing() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData, LocationCatalog.toolchains])
        progress.record(.unavailable(location: LocationCatalog.toolchains, reason: "permission denied"))

        #expect(progress.completedCount == 1)
        #expect(progress.reclaimableBytes == 0)
    }

    @Test("An unpromised row cannot push the count past the plan")
    func unpromisedRowDoesNotOvercount() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData])
        progress.record(entry(LocationCatalog.derivedData, bytes: 1))
        progress.record(entry(LocationCatalog.archives, bytes: 2))

        #expect(progress.completedCount == 1)
        #expect(progress.plannedCount == 1)
        #expect(progress.pending.isEmpty)
    }

    @Test("The same row landing twice is recorded once")
    func recordIsIdempotent() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData])
        progress.record(entry(LocationCatalog.derivedData, bytes: 5))
        progress.record(entry(LocationCatalog.derivedData, bytes: 5))

        #expect(progress.rows.count == 1)
        #expect(progress.reclaimableBytes == 5)
    }

    @Test("Reset clears every half, so a queued scan starts from nothing")
    func resetClearsEverything() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData])
        progress.begin(LocationCatalog.archives.id)
        progress.record(entry(LocationCatalog.derivedData, bytes: 5))

        progress.reset()

        #expect(!progress.hasPlan)
        #expect(progress.rows.isEmpty)
        #expect(progress.pending.isEmpty)
        #expect(progress.measuring.isEmpty)
        #expect(progress.reclaimableBytes == 0)
    }

    // MARK: - In flight

    @Test("A location measures from its start until its row lands")
    func measuringSpansStartToRow() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData, LocationCatalog.archives])
        #expect(progress.measuring.isEmpty)

        progress.begin(LocationCatalog.derivedData.id)

        #expect(progress.measuring == [LocationCatalog.derivedData.id])
        #expect(progress.isMeasuring(LocationCatalog.derivedData.id))
        #expect(!progress.isMeasuring(LocationCatalog.archives.id))

        progress.record(entry(LocationCatalog.derivedData, bytes: 5))

        #expect(progress.measuring.isEmpty)
        #expect(!progress.isMeasuring(LocationCatalog.derivedData.id))
    }

    @Test("An unpromised location never counts as measuring")
    func unpromisedLocationNeverMeasures() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData])

        progress.begin(LocationCatalog.archives.id)

        #expect(progress.measuring.isEmpty)
        #expect(!progress.isMeasuring(LocationCatalog.archives.id))
    }

    @Test("A partial rescan measures only the locations it promised")
    func partialRescanMeasuresOnlyItsOwn() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData])
        progress.begin(LocationCatalog.derivedData.id)
        progress.begin(LocationCatalog.toolchains.id)

        #expect(progress.measuring == [LocationCatalog.derivedData.id])
    }

    @Test("More than one location can be measuring at once")
    func concurrentMeasurements() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData, LocationCatalog.simulatorRuntimes])
        progress.begin(LocationCatalog.derivedData.id)
        progress.begin(LocationCatalog.simulatorRuntimes.id)

        #expect(progress.measuring == [LocationCatalog.derivedData.id, LocationCatalog.simulatorRuntimes.id])
    }

    @Test("Beginning a location does not advance the counter or the pending list")
    func beginDoesNotCountAsLanded() {
        var progress = ScanProgress()
        progress.plan([LocationCatalog.derivedData, LocationCatalog.archives])
        progress.begin(LocationCatalog.derivedData.id)

        #expect(progress.completedCount == 0)
        #expect(progress.pending.map(\.id) == [LocationCatalog.derivedData.id, LocationCatalog.archives.id])
        #expect(progress.rows.isEmpty)
    }
}
