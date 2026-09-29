import Foundation

/// A scan's rows in a form that survives a relaunch.
public struct InventorySnapshot: Codable, Sendable, Equatable {
    /// Bumped whenever the saved snapshot shape changes.
    public static let schemaVersion = 3

    /// What the row measured.
    public enum Kind: Codable, Sendable, Equatable {
        case sized(bytes: Int64)
        case unavailable(reason: String)
    }

    public struct RootRow: Codable, Sendable, Equatable {
        public let path: String
        public let allocatedBytes: Int64
        public let source: String?
        public let volumeIdentifier: String?
        public let layout: String?

        public init(
            path: String,
            allocatedBytes: Int64,
            source: String? = nil,
            volumeIdentifier: String? = nil,
            layout: String? = nil
        ) {
            self.path = path
            self.allocatedBytes = allocatedBytes
            self.source = source
            self.volumeIdentifier = volumeIdentifier
            self.layout = layout
        }
    }

    public struct Row: Codable, Sendable, Equatable {
        public let locationId: String
        public let kind: Kind
        public let lastUsedDate: Date?
        public let roots: [RootRow]
    }

    public let version: Int
    public let scannedAt: Date
    public let sizesAreUpperBound: Bool
    /// Aggregate eligible Gradle bytes only; drill-down listings are never persisted.
    public let optInReclaimableBytes: Int64?
    public let rows: [Row]

    public init(_ inventory: Inventory) {
        version = Self.schemaVersion
        scannedAt = inventory.scannedAt
        sizesAreUpperBound = inventory.sizesAreUpperBound
        optInReclaimableBytes = inventory.optInReclaimableBytes
        rows = inventory.entries.map { entry in
            Row(
                locationId: entry.location.id,
                kind: entry.unavailableReason.map(Kind.unavailable) ?? .sized(bytes: entry.reclaimableBytes),
                lastUsedDate: entry.staleness.lastUsedDate,
                roots: entry.roots.map {
                    RootRow(
                        path: $0.url.path(percentEncoded: false),
                        allocatedBytes: $0.allocatedBytes,
                        source: $0.source,
                        volumeIdentifier: $0.volumeIdentifier,
                        layout: $0.layout
                    )
                }
            )
        }
    }

    /// Rebuilds an inventory for display, with capacity supplied by the caller.
    public func inventory(
        capacity: VolumeCapacity,
        catalog: [TrackedLocation] = LocationCatalog.all
    ) -> Inventory? {
        guard (1 ... Self.schemaVersion).contains(version) else { return nil }

        let locationsById = Dictionary(catalog.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let entries = rows.compactMap { row -> InventoryEntry? in
            guard let location = locationsById[row.locationId] else { return nil }
            switch row.kind {
            case let .sized(bytes):
                return .sized(
                    location: location,
                    reclaimableBytes: bytes,
                    staleness: StalenessInfo(lastUsedDate: row.lastUsedDate),
                    roots: row.roots.map {
                        RootSize(
                            url: URL(fileURLWithPath: $0.path),
                            allocatedBytes: $0.allocatedBytes,
                            source: $0.source,
                            volumeIdentifier: $0.volumeIdentifier,
                            layout: $0.layout
                        )
                    }
                )
            case let .unavailable(reason):
                return .unavailable(location: location, reason: reason)
            }
        }

        guard !entries.isEmpty else { return nil }

        let includesGradleCaches = entries.contains { $0.location.id == LocationCatalog.gradleCaches.id }

        return Inventory(
            entries: entries,
            capacity: capacity,
            scannedAt: scannedAt,
            sizesAreUpperBound: sizesAreUpperBound,
            optInReclaimableBytes: includesGradleCaches ? optInReclaimableBytes ?? 0 : 0
        )
    }
}
