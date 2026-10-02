import Foundation

extension ScanEngine {
    public func cachedInventory() -> Inventory? {
        cachedCurrentInventory
    }

    public func invalidate(generation: UInt64? = nil) {
        if let generation {
            guard generation >= currentGeneration else { return }
            currentGeneration = generation
        }
        cachedCurrentInventory = nil
        childSizeCache = [:]
        cachedGradleCacheCleanableBytes = 0
    }

    /// Sizes of a location's immediate children, keyed by name, flattened across its roots.
    public func childSizes(for locationId: String) -> [String: Int64] {
        guard let byRoot = childSizeCache[locationId] else { return [:] }
        return Self.immediateChildSizes(in: byRoot)
    }
}
