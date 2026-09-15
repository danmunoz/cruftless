import Foundation

/// How a tracked location's contents may be mutated.
public enum MutationPolicy: Sendable, Hashable {
    /// Paths under the location's roots are deleted through `PathGuard`.
    case pathDeletion
    /// Everything goes through `simctl`.
    case simctl
}

/// Where a tracked location's size comes from.
public enum SizeSource: Sendable, Hashable {
    /// Walk the location's resolved filesystem roots.
    case filesystemRoots
    /// Size from `SimulatorService.runtimes()`.
    case simulatorRuntimes
}

/// Defines a tracked bloat location, its tier, icon, staleness logic, and root directories.
public struct TrackedLocation: Sendable, Hashable, Identifiable {
    public let id: String
    public let title: String
    public let icon: RowIcon
    public let tier: Tier
    public let hasDrillDown: Bool
    public let stalenessSource: StalenessSource
    public let sizeSource: SizeSource
    public let mutationPolicy: MutationPolicy
    public let resolveRoots: @Sendable () -> [URL]

    public let consequence: String

    /// The roots this location has when nothing outside the app redirects it.
    public let resolveDefaultRoots: (@Sendable () -> [URL])?

    public init(
        id: String,
        title: String,
        icon: RowIcon,
        tier: Tier,
        hasDrillDown: Bool,
        stalenessSource: StalenessSource,
        sizeSource: SizeSource = .filesystemRoots,
        mutationPolicy: MutationPolicy = .pathDeletion,
        consequence: String? = nil,
        resolveRoots: @escaping @Sendable () -> [URL],
        resolveDefaultRoots: (@Sendable () -> [URL])? = nil
    ) {
        self.id = id
        self.title = title
        self.icon = icon
        self.tier = tier
        self.hasDrillDown = hasDrillDown
        self.stalenessSource = stalenessSource
        self.sizeSource = sizeSource
        self.mutationPolicy = mutationPolicy
        self.consequence = consequence ?? Self.defaultConsequence(for: tier)
        self.resolveRoots = resolveRoots
        self.resolveDefaultRoots = resolveDefaultRoots
    }

    /// The fallback consequence for a location with nothing more specific to say: what its tier already promises.
    public static func defaultConsequence(for tier: Tier) -> String {
        switch tier {
        case .regen: "Xcode recreates this on the next build."
        case .judgment: "Needs a re-download or reinstall if you want it back."
        case .irreversible: "This cannot be recovered."
        case .reveal: "Reveal in Finder."
        case .info: "Root-owned. Run the copied command in Terminal to delete."
        }
    }

    /// True when `root` is not one of this location's default roots: it was redirected by configuration this app does not own.
    public func isCustomRoot(_ root: URL) -> Bool {
        guard let resolveDefaultRoots else { return false }
        let rootPath = ProtectedPaths.normalize(root)
        return !resolveDefaultRoots().contains { ProtectedPaths.normalize($0) == rootPath }
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    public static func == (lhs: TrackedLocation, rhs: TrackedLocation) -> Bool {
        lhs.id == rhs.id
    }
}
