import Foundation

/// The consolidated disk inventory produced by a scan.
public struct Inventory: Sendable, Hashable {
    public let entries: [InventoryEntry]
    public let capacity: VolumeCapacity
    public let scannedAt: Date
    public let sizesAreUpperBound: Bool

    /// Total reclaimable bytes across the `regen`, `judgment` and `irreversible` entries.
    public var reclaimableBytes: Int64 {
        entries.reduce(0) { total, entry in
            switch entry {
            case let .sized(loc, bytes, _, _):
                if loc.tier.isDeletable {
                    return total + bytes
                }
                return total
            case .unavailable:
                return total
            }
        }
    }

    public init(
        entries: [InventoryEntry],
        capacity: VolumeCapacity,
        scannedAt: Date = Date(),
        sizesAreUpperBound: Bool = true
    ) {
        self.entries = Self.displaySorted(entries)
        self.capacity = capacity
        self.scannedAt = scannedAt
        self.sizesAreUpperBound = sizesAreUpperBound
    }

    /// Sorts by bytes, catalog order, title, then ID.
    static func displaySorted(_ entries: [InventoryEntry]) -> [InventoryEntry] {
        let catalogOrder = Dictionary(
            uniqueKeysWithValues: LocationCatalog.all.enumerated().map { ($0.element.id, $0.offset) }
        )
        return entries.sorted { lhs, rhs in
            if lhs.reclaimableBytes != rhs.reclaimableBytes {
                return lhs.reclaimableBytes > rhs.reclaimableBytes
            }
            let leftOrder = catalogOrder[lhs.location.id] ?? Int.max
            let rightOrder = catalogOrder[rhs.location.id] ?? Int.max
            if leftOrder != rightOrder { return leftOrder < rightOrder }
            if lhs.location.title != rhs.location.title {
                return lhs.location.title < rhs.location.title
            }
            return lhs.location.id < rhs.location.id
        }
    }

    /// Rows that show a size: sized entries above 0 B, in display order.
    public var sizedRows: [InventoryEntry] {
        entries.filter { entry in
            if case .sized = entry { return entry.reclaimableBytes > 0 }
            return false
        }
    }

    /// Rows with nothing to show, in display order: entries measured at 0 B, then unavailable entries.
    public var zeroOrUnavailableRows: [InventoryEntry] {
        let zeros = entries.filter { entry in
            if case .sized = entry { return entry.reclaimableBytes == 0 }
            return false
        }
        return zeros + entries.filter(\.isUnavailable)
    }
}
