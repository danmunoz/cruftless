import Foundation

/// What the gate says about opening one path.
public enum AccessDecision: Sendable, Hashable {
    case clear
    /// In a protected area macOS has not asked about yet; opening it would raise an alert.
    case blocked(ProtectedArea)
}

/// The single entry point every walk and content read of an outside path passes before it opens anything.
public struct AccessGate: Sendable {
    public let classifier: ProtectedAreaClassifier
    public let ledger: AccessLedger

    public init(classifier: ProtectedAreaClassifier, ledger: AccessLedger) {
        self.classifier = classifier
        self.ledger = ledger
    }

    /// The gate the app runs with.
    public static let shared = AccessGate(classifier: .standard, ledger: .shared)

    public func check(_ url: URL) -> AccessDecision {
        guard let area = classifier.area(for: url), !ledger.hasAsked(area) else { return .clear }
        return .blocked(area)
    }

    /// Splits a location's roots into the ones that may be opened and the ones that may not.
    public func partition(_ roots: [URL], for location: TrackedLocation) -> GatedRoots {
        var clear: [URL] = []
        var askedAreas: [String: ProtectedArea] = [:]
        var blocked: [BlockedAccess] = []
        for root in roots {
            guard let area = classifier.area(for: root) else {
                clear.append(root)
                continue
            }
            if ledger.hasAsked(area) {
                clear.append(root)
                askedAreas[ProtectedPaths.normalize(root)] = area
            } else {
                blocked.append(BlockedAccess(
                    path: root.path(percentEncoded: false),
                    area: area,
                    state: .notAsked,
                    reason: AccessReason.title(for: location, root: root)
                ))
            }
        }
        return GatedRoots(clear: clear, blocked: blocked, askedAreas: askedAreas)
    }

    /// The roots of `roots` that may be opened.
    public func clearRoots(_ roots: [URL]) -> [URL] {
        roots.filter { check($0) == .clear }
    }
}

/// A location's roots after the gate: only `clear` may be walked, read or listed.
public struct GatedRoots: Sendable {
    public let clear: [URL]
    public let blocked: [BlockedAccess]
    /// Clear roots that lie in an area already asked about, keyed by normalized path.
    let askedAreas: [String: ProtectedArea]

    fileprivate init(clear: [URL], blocked: [BlockedAccess], askedAreas: [String: ProtectedArea]) {
        self.clear = clear
        self.blocked = blocked
        self.askedAreas = askedAreas
    }

    /// Every root, blocked ones included, for checks that use metadata only.
    public var all: [URL] {
        clear + blocked.map { URL(fileURLWithPath: $0.path, isDirectory: true) }
    }

    /// The asked area a clear root lies in, if any.
    func askedArea(of root: URL) -> ProtectedArea? {
        askedAreas[ProtectedPaths.normalize(root)]
    }
}

/// How a protected root is named to the user.
public enum AccessReason {
    public static func title(for location: TrackedLocation, root: URL) -> String {
        if AtomicBundles.isAtomicBundle(root) { return root.lastPathComponent }
        if location.id == LocationCatalog.derivedData.id { return "Derived Data location" }
        if location.id == LocationCatalog.archives.id { return "Archives location" }
        return location.title
    }
}
