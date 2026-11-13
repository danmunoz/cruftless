import Foundation

public extension ScanEngine {
    func cachedInventory() -> Inventory? {
        cachedCurrentInventory
    }

    /// Drops everything measured; with a generation, only when it is newer than the one already admitted.
    func invalidate(generation: UInt64? = nil) {
        guard let generation else {
            clearCaches()
            return
        }
        _ = adopt(generation)
    }

    /// Admits a request's generation, and reports whether it may run; a newer one discards what older ones measured.
    internal func adopt(_ generation: UInt64) -> Bool {
        guard generation >= currentGeneration else { return false }
        if generation > currentGeneration {
            currentGeneration = generation
            clearCaches()
        }
        return true
    }

    private func clearCaches() {
        cachedCurrentInventory = nil
        childSizeCache = [:]
        cachedGradleCacheCleanableBytes = 0
    }

    /// Sizes of a location's immediate children, keyed by name, flattened across its roots.
    func childSizes(for locationId: String) -> [String: Int64] {
        guard let byRoot = childSizeCache[locationId] else { return [:] }
        return Self.immediateChildSizes(in: byRoot)
    }
}
