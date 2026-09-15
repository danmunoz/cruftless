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
        self.entries = entries.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        self.capacity = capacity
        self.scannedAt = scannedAt
        self.sizesAreUpperBound = sizesAreUpperBound
    }
}
