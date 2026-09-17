import Foundation

public struct ScanProgress: Sendable, Equatable {
    /// The locations this scan said it would report on, in catalog order.
    public private(set) var planned: [TrackedLocation] = []

    /// Rows as they arrived, in the order they were measured.
    public private(set) var landed: [InventoryEntry] = []

    /// Locations whose measurement has begun, whether or not it has finished.
    public private(set) var started: Set<String> = []

    public init() {}

    /// True once the scan has said what it will cover.
    public var hasPlan: Bool {
        !planned.isEmpty
    }

    public mutating func plan(_ locations: [TrackedLocation]) {
        planned = locations
    }

    public mutating func begin(_ locationId: String) {
        started.insert(locationId)
    }

    public mutating func record(_ entry: InventoryEntry) {
        guard !landed.contains(where: { $0.id == entry.id }) else { return }
        landed.append(entry)
    }

    public mutating func reset() {
        planned = []
        landed = []
        started = []
    }

    /// Measured rows in final inventory order.
    public var rows: [InventoryEntry] {
        Inventory.displaySorted(landed)
    }

    /// Planned locations without measurements.
    public var pending: [TrackedLocation] {
        let landedIds = Set(landed.map(\.id))
        return planned.filter { !landedIds.contains($0.id) }
    }

    /// Planned locations currently being measured.
    public var measuring: Set<String> {
        let landedIds = Set(landed.map(\.id))
        let plannedIds = Set(planned.map(\.id))
        return started.intersection(plannedIds).subtracting(landedIds)
    }

    /// Returns whether a location is being measured.
    public func isMeasuring(_ locationId: String) -> Bool {
        measuring.contains(locationId)
    }

    public var plannedCount: Int {
        planned.count
    }

    public var completedCount: Int {
        planned.count - pending.count
    }

    public var reclaimableBytes: Int64 {
        landed.reduce(0) { total, entry in
            entry.location.tier.isDeletable ? total + entry.reclaimableBytes : total
        }
    }
}
