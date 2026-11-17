import Foundation

/// One root of a tracked location together with what that root alone holds.
public struct RootSize: Sendable, Hashable {
    public let url: URL
    public let allocatedBytes: Int64
    public let source: String?
    public let volumeIdentifier: String?
    public let layout: String?

    public init(
        url: URL,
        allocatedBytes: Int64,
        source: String? = nil,
        volumeIdentifier: String? = nil,
        layout: String? = nil
    ) {
        self.url = url
        self.allocatedBytes = allocatedBytes
        self.source = source
        self.volumeIdentifier = volumeIdentifier
        self.layout = layout
    }
}

public enum InventoryEntry: Sendable, Hashable, Identifiable {
    case sized(
        location: TrackedLocation,
        reclaimableBytes: Int64,
        staleness: StalenessInfo,
        roots: [RootSize],
        eligibleCleanupBytes: Int64? = nil,
        /// Roots left unmeasured because of a protected area, beside the ones measured.
        accessNeed: LocationAccessNeed? = nil
    )
    case unavailable(
        location: TrackedLocation,
        reason: String
    )
    /// Nothing measured: every root lies in a protected area that is blocked or refused.
    case needsAccess(
        location: TrackedLocation,
        need: LocationAccessNeed
    )

    public var id: String {
        location.id
    }

    public var location: TrackedLocation {
        switch self {
        case let .sized(loc, _, _, _, _, _):
            loc
        case let .unavailable(loc, _), let .needsAccess(loc, _):
            loc
        }
    }

    public var reclaimableBytes: Int64 {
        switch self {
        case let .sized(_, bytes, _, _, _, _):
            bytes
        case .unavailable, .needsAccess:
            0
        }
    }

    public var eligibleCleanupBytes: Int64 {
        switch self {
        case let .sized(location, bytes, _, _, explicit, _):
            guard location.mutationPolicy != .readOnly, location.tier.isDeletable else { return 0 }
            return min(max(0, explicit ?? bytes), max(0, bytes))
        case .unavailable, .needsAccess: return 0
        }
    }

    public var staleness: StalenessInfo {
        switch self {
        case let .sized(_, _, staleness, _, _, _):
            staleness
        case .unavailable, .needsAccess:
            StalenessInfo(lastUsedDate: nil)
        }
    }

    /// True when the row has no measurement to show or act on.
    public var isUnavailable: Bool {
        switch self {
        case .sized: false
        case .unavailable, .needsAccess: true
        }
    }

    public var unavailableReason: String? {
        switch self {
        case .sized: nil
        case let .unavailable(_, reason): reason
        case let .needsAccess(_, need): need.message
        }
    }

    /// The protected-area roots this row did not measure, whether it measured others or nothing.
    public var accessNeed: LocationAccessNeed? {
        switch self {
        case let .sized(_, _, _, _, _, need): need
        case .unavailable: nil
        case let .needsAccess(_, need): need
        }
    }

    public var roots: [RootSize] {
        switch self {
        case let .sized(_, _, _, roots, _, _):
            roots
        case .unavailable, .needsAccess:
            []
        }
    }

    public var rootURLs: [URL] {
        roots.map(\.url)
    }
}
