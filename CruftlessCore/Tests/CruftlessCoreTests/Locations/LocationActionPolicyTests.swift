@testable import CruftlessCore
import Foundation
import Testing

@Suite("Location action policy")
struct LocationActionPolicyTests {
    private func sized(_ location: TrackedLocation, bytes: Int64) -> InventoryEntry {
        .sized(location: location, reclaimableBytes: bytes, staleness: StalenessInfo(lastUsedDate: nil), roots: [])
    }

    @Test("A location without whole-location clear is refused by the planner", arguments: LocationCatalog.all)
    func clearPolicyMatchesPlanner(location: TrackedLocation) {
        do {
            _ = try DeletionPlanner.wholeLocation(sized(location, bytes: 1_000), context: PlanningContext())
            Issue.record("\(location.id) planned with no roots")
        } catch let error as DeletionPlanningError {
            let isPolicyRefusal = switch error {
            case .notDeletable, .flaggedLocation, .simulatorLocation, .readOnlyLocation: true
            default: false
            }
            #expect(isPolicyRefusal == !location.supportsWholeLocationClear, "\(location.id): \(error)")
        } catch {
            Issue.record("\(location.id): \(error)")
        }
    }

    @Test("Simulator locations never offer a whole-location clear")
    func simulatorLocationsOfferNoClear() {
        for location in [LocationCatalog.simulatorDevices, LocationCatalog.xctestDevices, LocationCatalog.simulatorRuntimes] {
            #expect(!location.supportsWholeLocationClear)
            #expect(!sized(location, bytes: 1_000).canClearWholeLocation)
        }
    }

    @Test("An empty or unavailable row offers no clear")
    func emptyRowOffersNoClear() {
        #expect(sized(LocationCatalog.derivedData, bytes: 1_000).canClearWholeLocation)
        #expect(!sized(LocationCatalog.derivedData, bytes: 0).canClearWholeLocation)
        #expect(!InventoryEntry.unavailable(location: LocationCatalog.derivedData, reason: "denied").canClearWholeLocation)
    }

    @Test("Select Items is offered only where several children can share one review")
    func batchSelectionLocations() {
        let ids = Set(LocationCatalog.all.filter(\.supportsBatchSelection).map(\.id))
        #expect(ids == [
            LocationCatalog.deviceSupport.id,
            LocationCatalog.simulatorDevices.id,
            LocationCatalog.xctestDevices.id,
            LocationCatalog.simulatorRuntimes.id,
            LocationCatalog.derivedData.id,
            LocationCatalog.toolchains.id,
            LocationCatalog.archives.id
        ])
    }
}
