import Foundation

/// One thing that needs a protected area, named for the user.
public struct AccessNeedReason: Sendable, Hashable {
    public let locationId: String
    public let title: String
    public let path: String

    public init(locationId: String, title: String, path: String) {
        self.locationId = locationId
        self.title = title
        self.path = path
    }
}

/// Everything that needs one protected area.
public struct AreaAccessNeed: Sendable, Hashable {
    public let area: ProtectedArea
    /// Whether macOS has already asked about this area.
    public let isAsked: Bool
    public let reasons: [AccessNeedReason]

    public init(area: ProtectedArea, isAsked: Bool, reasons: [AccessNeedReason]) {
        self.area = area
        self.isAsked = isAsked
        self.reasons = reasons
    }
}

/// Finds which protected areas the tracked locations reach into, using metadata only.
public enum AccessPreflight {
    /// Resolves the catalog's roots, including the Spotlight lookup for Xcode installs, and groups the protected ones by area.
    public static func needs(
        catalog: [TrackedLocation] = LocationCatalog.all,
        gate: AccessGate = .shared
    ) async -> [AreaAccessNeed] {
        if catalog.contains(where: { $0.id == LocationCatalog.xcodeInstalls.id }) {
            await RootResolver.prepare()
        }
        return needs(resolved: catalog.map { ($0, $0.resolveRoots()) }, gate: gate)
    }

    /// Groups already resolved roots that exist and lie in a protected area, in `ProtectedArea` order.
    public static func needs(resolved: [(TrackedLocation, [URL])], gate: AccessGate) -> [AreaAccessNeed] {
        var reasons: [ProtectedArea: [AccessNeedReason]] = [:]
        for (location, roots) in resolved where location.sizeSource == .filesystemRoots {
            for root in roots {
                let path = root.path(percentEncoded: false)
                guard FileManager.default.fileExists(atPath: path),
                      let area = gate.classifier.area(for: root)
                else { continue }
                let reason = AccessNeedReason(
                    locationId: location.id,
                    title: AccessReason.title(for: location, root: root),
                    path: path
                )
                if reasons[area]?.contains(reason) != true {
                    reasons[area, default: []].append(reason)
                }
            }
        }
        return ProtectedArea.allCases.compactMap { area in
            guard let found = reasons[area] else { return nil }
            return AreaAccessNeed(area: area, isAsked: gate.ledger.hasAsked(area), reasons: found)
        }
    }
}
