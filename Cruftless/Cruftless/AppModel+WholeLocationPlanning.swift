import CruftlessCore

extension AppModel {
    func planWholeLocation(_ entry: InventoryEntry) async {
        guard !isDeleting else { return }
        let location = entry.location
        let catalog = settings.activeCatalog
        guard catalog.locations.contains(where: { $0.id == location.id }) else { return }
        guard !isRestored(entry) else {
            refuseActionOnRestoredInventory()
            return
        }
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
              currentCatalog.locations.contains(where: { $0.id == location.id }), !isDeleting
        else { return }
        plan { context in
            try DeletionPlanner.wholeLocation(entry, context: context.withChildren { _ in children })
        }
    }
}
