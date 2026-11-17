import Foundation

public struct ChildEntry: Sendable, Hashable, Identifiable {
    public let id: String
    public let name: String
    public let url: URL
    public let reclaimableBytes: Int64
    public let staleness: StalenessInfo
    public let tier: Tier
    public let consequence: String
    /// The project a Derived Data folder was built from; `nil` for every other location.
    public let workspace: DerivedDataWorkspace?

    public var isFlagged: Bool {
        tier.isFlagged
    }

    public init(
        id: String,
        name: String,
        url: URL,
        reclaimableBytes: Int64,
        staleness: StalenessInfo,
        tier: Tier,
        consequence: String,
        workspace: DerivedDataWorkspace? = nil
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.reclaimableBytes = reclaimableBytes
        self.staleness = staleness
        self.tier = tier
        self.consequence = consequence
        self.workspace = workspace
    }

    public var isOrphanedProject: Bool {
        workspace?.isOrphaned ?? false
    }
}
