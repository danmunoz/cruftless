import Foundation

/// What a scan reports as it runs.
public enum ScanEvent: Sendable {
    case started
    /// The locations this scan will report on, in catalog order, before any of them has been measured.
    case planned([TrackedLocation])
    /// This location is being measured *right now*.
    case locationStarted(locationId: String)
    case locationScanned(InventoryEntry)
    /// What that location's drill-down should render, measured by the same walk that produced the row.
    case locationContents(locationId: String, DrillDownContent)
    case completed(Inventory)
    /// A location whose size is incomplete: an unreadable subfolder, say.
    case failed(locationId: String, reason: String)
}
