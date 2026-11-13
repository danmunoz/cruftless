import CruftlessCore
import Foundation

extension AppModel {
    func planWholeLocation(_ entry: InventoryEntry) async {
        let location = entry.location
        guard planningLocationId == nil else { return }
        guard !isDeleting else {
            reportPlanFailure(DeletionPlanningError.deletionInProgress.localizedDescription)
            return
        }
        let catalog = settings.activeCatalog
        guard catalog.locations.contains(where: { $0.id == location.id }) else {
            reportPlanFailure(DeletionPlanningError.inventoryChanged(title: location.title).localizedDescription)
            return
        }
        guard !isRestored(entry) else {
            refuseActionOnRestoredInventory()
            return
        }
        planningLocationId = location.id
        defer { planningLocationId = nil }
        let children: [ChildEntry] = if entry.roots.contains(where: { location.isCustomRoot($0.url) }) {
            if let listed = drillDowns[location.id]?.children {
                listed
            } else {
                await scanEngine.children(of: location.id)
            }
        } else {
            []
        }
        let currentCatalog = settings.activeCatalog
        guard currentCatalog.generation == catalog.generation,
              currentCatalog.locations.contains(where: { $0.id == location.id })
        else {
            reportPlanFailure(DeletionPlanningError.inventoryChanged(title: location.title).localizedDescription)
            return
        }
        guard !isDeleting else {
            reportPlanFailure(DeletionPlanningError.deletionInProgress.localizedDescription)
            return
        }
        plan { context in
            try DeletionPlanner.wholeLocation(entry, context: context.withChildren { _ in children })
        }
    }
}
