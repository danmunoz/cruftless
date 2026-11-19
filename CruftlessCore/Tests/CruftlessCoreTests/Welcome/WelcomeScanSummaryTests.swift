@testable import CruftlessCore
import Foundation
import Testing

@Suite("Welcome scan summary")
struct WelcomeScanSummaryTests {
    private let capacity = VolumeCapacity(
        totalBytes: 500_000_000_000,
        freeBytes: 50_000_000_000,
        purgeableBytes: 0,
        usedBytes: 450_000_000_000
    )

    private func sized(_ location: TrackedLocation, _ bytes: Int64) -> InventoryEntry {
        .sized(
            location: location,
            reclaimableBytes: bytes,
            staleness: StalenessInfo(lastUsedDate: nil),
            roots: [RootSize(url: URL(fileURLWithPath: "/tmp/\(location.id)"), allocatedBytes: bytes)]
        )
    }

    private func blocked(_ location: TrackedLocation, state: AreaAccessState, reason: String) -> InventoryEntry {
        .needsAccess(
            location: location,
            need: LocationAccessNeed(
                blocked: [BlockedAccess(path: "/Volumes/Backup/\(location.id)", area: .removableVolume, state: state, reason: reason)],
                measuredRootCount: 0
            )
        )
    }

    private func summary(
        progress: ScanProgress = ScanProgress(),
        inventory: Inventory? = nil,
        isScanning: Bool = false,
        failure: String? = nil
    ) -> WelcomeScanSummary {
        WelcomeScanSummary.make(progress: progress, inventory: inventory, isScanning: isScanning, failure: failure)
    }

    @Test("Before the scan reports anything the summary is starting and empty")
    func starting() {
        let idle = summary()
        #expect(idle.phase == .starting)
        #expect(idle.rows.isEmpty)
        #expect(idle.progressCaption == nil)

        #expect(summary(isScanning: true).phase == .starting)
    }

    @Test("A scan that ended without an inventory reports its failure")
    func failed() {
        #expect(summary(failure: "Derived Data: unreadable").phase == .failed("Derived Data: unreadable"))
    }

    @Test("A running scan shows what landed, then what is being measured, then what waits")
    func scanning() {
        var progress = ScanProgress()
        progress.plan(LocationCatalog.all)
        progress.record(sized(LocationCatalog.derivedData, 18_000_000_000))
        progress.record(sized(LocationCatalog.simulatorDevices, 9_000_000_000))
        progress.begin(LocationCatalog.swiftPMCache.id)

        let running = summary(progress: progress, isScanning: true)
        #expect(running.phase == .scanning)
        #expect(running.rows.count == 5)
        #expect(running.rows.map(\.id).prefix(3) == [
            LocationCatalog.derivedData.id, LocationCatalog.simulatorDevices.id, LocationCatalog.swiftPMCache.id
        ])
        #expect(running.rows[0].detail == .size(18_000_000_000))
        #expect(running.rows[2].detail == .measuring)
        #expect(running.rows[3].detail == .waiting)
        #expect(running.progressCaption == "2 of \(LocationCatalog.all.count) locations")
        #expect(running.totalCaption == "cleanable so far")
        #expect(running.accessNote == nil)
    }

    @Test("A running scan always keeps one row for what is still to come")
    func scanningKeepsAPendingRow() {
        var progress = ScanProgress()
        progress.plan(LocationCatalog.all)
        for (offset, location) in LocationCatalog.all.prefix(8).enumerated() {
            progress.record(sized(location, Int64(offset + 1) * 1_000_000_000))
        }

        let rows = summary(progress: progress, isScanning: true).rows
        #expect(rows.count == 5)
        #expect(rows.last?.detail == .waiting)
    }

    @Test("A finished scan folds the rows that do not fit into a remainder that keeps the sum")
    func finishedFoldsRemainder() {
        let entries = LocationCatalog.all.prefix(8).enumerated().map { offset, location in
            sized(location, Int64(offset + 1) * 1_000_000_000)
        }
        let finished = summary(inventory: Inventory(entries: entries, capacity: capacity))

        #expect(finished.phase == .finished)
        #expect(finished.rows.count == 4)
        #expect(finished.remainder?.count == 4)
        let shownBytes = finished.rows.reduce(Int64(0)) { total, row in
            if case let .size(bytes) = row.detail { total + bytes } else { total }
        }
        #expect(shownBytes + (finished.remainder?.bytes ?? 0) == 36_000_000_000)
        #expect(finished.totalCaption == "cleanable in 8 locations")
        #expect(finished.accessNote == nil)
        #expect(finished.accessActionTitle == nil)
    }

    @Test("A finished scan with few rows shows them all")
    func finishedShowsAll() {
        let entries = [sized(LocationCatalog.derivedData, 2_000_000_000), sized(LocationCatalog.swiftPMCache, 1_000_000_000)]
        let finished = summary(inventory: Inventory(entries: entries, capacity: capacity))
        #expect(finished.rows.count == 2)
        #expect(finished.remainder == nil)
    }

    @Test("A finished inventory wins over a scan still reporting")
    func inventoryWins() {
        let inventory = Inventory(entries: [sized(LocationCatalog.derivedData, 1_000_000_000)], capacity: capacity)
        #expect(summary(inventory: inventory, isScanning: true).isFinished)
    }

    @Test("A place that was never asked about is named, with the action that allows it")
    func notAskedAccess() {
        let entries = [
            sized(LocationCatalog.derivedData, 2_000_000_000),
            blocked(LocationCatalog.archives, state: .notAsked, reason: "Archives location")
        ]
        let finished = summary(inventory: Inventory(entries: entries, capacity: capacity))

        #expect(finished.accessNote == "Archives location was not measured. Nothing there was read.")
        #expect(finished.accessActionTitle == "Allow Access")
        #expect(finished.totalCaption == "cleanable in 1 of 2 locations")
        #expect(finished.rows.last?.detail == .note("Needs access to an external drive"))
    }

    @Test("A refused place offers a review instead, and the note takes one row's room")
    func refusedAccess() {
        let entries = LocationCatalog.all.prefix(7).enumerated().map { offset, location in
            sized(location, Int64(offset + 1) * 1_000_000_000)
        } + [blocked(LocationCatalog.archives, state: .notAllowed, reason: "Archives location")]
        let finished = summary(inventory: Inventory(entries: entries, capacity: capacity))

        #expect(finished.accessActionTitle == "Review Access")
        #expect(finished.rows.count == 3)
        #expect(finished.remainder?.count == 5)
    }

    @Test("Flagged locations keep their marker")
    func flaggedRows() {
        let finished = summary(inventory: Inventory(entries: [sized(LocationCatalog.archives, 1_000_000_000)], capacity: capacity))
        #expect(finished.rows.first?.isFlagged == true)
    }
}
