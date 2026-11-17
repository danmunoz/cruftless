import Foundation

/// The Derived Data folders whose project is gone, offered as one selection that still goes through Review.
public struct OrphanedProjectsSuggestion: Sendable, Equatable {
    public let childIDs: Set<String>
    public let reclaimableBytes: Int64

    public var count: Int {
        childIDs.count
    }

    /// `nil` when no selectable folder is orphaned; protected and flagged folders are left out.
    public init?(children: [ChildEntry], protectedPaths: ProtectedPaths) {
        let orphaned = children.filter { child in
            child.isOrphanedProject
                && child.tier.isDeletable
                && !child.isFlagged
                && !protectedPaths.isProtected(child.url)
                && !protectedPaths.containsProtectedDescendant(in: child.url)
        }
        guard !orphaned.isEmpty else { return nil }
        childIDs = Set(orphaned.map(\.id))
        reclaimableBytes = orphaned.reduce(0) { $0 + max(0, $1.reclaimableBytes) }
    }
}
