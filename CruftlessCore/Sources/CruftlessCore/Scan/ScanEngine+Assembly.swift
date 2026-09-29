import Foundation

extension ScanEngine {
    /// Assembles scan rows and retains unscanned rows during a partial rescan.
    nonisolated static func assembledInventory(
        from entries: [InventoryEntry],
        scanned: [TrackedLocation],
        capacity: VolumeCapacity,
        cachedInventory: Inventory?,
        optInReclaimableBytes: Int64
    ) -> Inventory {
        let assembledEntries: [InventoryEntry]
        if let cachedInventory {
            let rescannedIds = Set(scanned.map(\.id))
            assembledEntries = cachedInventory.entries.filter { !rescannedIds.contains($0.id) } + entries
        } else {
            assembledEntries = entries
        }

        return Inventory(
            entries: assembledEntries,
            capacity: capacity,
            scannedAt: Date(),
            sizesAreUpperBound: true,
            optInReclaimableBytes: optInReclaimableBytes
        )
    }
}
