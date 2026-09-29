import Foundation

public enum DevelopmentPlatform: String, CaseIterable, Codable, Sendable, Hashable {
    case apple
    case android
}

/// A validated platform scope. Empty selections always fall back to Apple.
public struct PlatformSelection: Sendable, Hashable {
    public let platforms: Set<DevelopmentPlatform>

    public init(_ platforms: Set<DevelopmentPlatform>) {
        self.platforms = platforms.isEmpty ? [.apple] : platforms
    }

    public static let appleOnly = PlatformSelection([.apple])
    public static let androidOnly = PlatformSelection([.android])
    public static let all = PlatformSelection(Set(DevelopmentPlatform.allCases))

    public static func migrate(_ values: [String]?) -> PlatformSelection {
        let recognized = Set((values ?? []).compactMap(DevelopmentPlatform.init(rawValue:)))
        return PlatformSelection(recognized)
    }

    public var identifiers: [String] {
        DevelopmentPlatform.allCases.filter(platforms.contains).map(\.rawValue)
    }

    public func catalog(generation: UInt64 = 0) -> ActiveCatalog {
        ActiveCatalog(selection: self, generation: generation)
    }
}

/// Immutable scope passed through scans, discovery and planning.
public struct ActiveCatalog: Sendable, Hashable {
    public let selection: PlatformSelection
    public let generation: UInt64

    public init(selection: PlatformSelection, generation: UInt64) {
        self.selection = selection
        self.generation = generation
    }

    public var locations: [TrackedLocation] {
        LocationCatalog.all.filter { selection.platforms.contains($0.platform) }
    }

    public var ids: Set<String> {
        Set(locations.map(\.id))
    }
}
