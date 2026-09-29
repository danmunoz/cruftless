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
        roots: [RootSize]
    )
    case unavailable(
        location: TrackedLocation,
        reason: String
    )

    public var id: String {
        location.id
    }

    public var location: TrackedLocation {
        switch self {
        case let .sized(loc, _, _, _):
            loc
        case let .unavailable(loc, _):
            loc
        }
    }

    public var reclaimableBytes: Int64 {
        switch self {
        case let .sized(_, bytes, _, _):
            bytes
        case .unavailable:
            0
        }
    }

    public var staleness: StalenessInfo {
        switch self {
        case let .sized(_, _, staleness, _):
            staleness
        case .unavailable:
            StalenessInfo(lastUsedDate: nil)
        }
    }

    public var isUnavailable: Bool {
        if case .unavailable = self { return true }
        return false
    }

    public var unavailableReason: String? {
        if case let .unavailable(_, reason) = self { return reason }
        return nil
    }

    public var roots: [RootSize] {
        switch self {
        case let .sized(_, _, _, roots):
            roots
        case .unavailable:
            []
        }
    }

    public var rootURLs: [URL] {
        roots.map(\.url)
    }
}
