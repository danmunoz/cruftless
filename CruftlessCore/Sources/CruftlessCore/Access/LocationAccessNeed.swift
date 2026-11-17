import Foundation

/// One root that was not walked because of a protected area.
public struct BlockedAccess: Sendable, Hashable, Codable {
    public let path: String
    public let area: ProtectedArea
    public let state: AreaAccessState
    /// What the root is, for the user: an Xcode copy's name, "Derived Data location".
    public let reason: String

    public init(path: String, area: ProtectedArea, state: AreaAccessState, reason: String) {
        self.path = path
        self.area = area
        self.state = state
        self.reason = reason
    }
}

/// Why a location, or part of it, was not measured.
public struct LocationAccessNeed: Sendable, Hashable, Codable {
    public let blocked: [BlockedAccess]
    /// How many of the location's roots were measured beside the blocked ones.
    public let measuredRootCount: Int

    public init(blocked: [BlockedAccess], measuredRootCount: Int) {
        self.blocked = blocked
        self.measuredRootCount = measuredRootCount
    }

    public var notMeasuredCount: Int {
        blocked.count
    }

    public var isPartial: Bool {
        measuredRootCount > 0
    }

    /// The areas involved, in first-seen order.
    public var areas: [ProtectedArea] {
        var seen: Set<ProtectedArea> = []
        return blocked.map(\.area).filter { seen.insert($0).inserted }
    }

    /// True when every blocked root was refused by macOS rather than never asked.
    public var isNotAllowed: Bool {
        !blocked.isEmpty && blocked.allSatisfy { $0.state == .notAllowed }
    }

    /// The areas as one phrase: "Documents and Downloads".
    public var areaNames: String {
        ListFormatter.localizedString(byJoining: areas.map(\.displayName))
    }

    /// Short copy for a row: "Needs access to Documents".
    public var summary: String {
        isNotAllowed ? "macOS does not allow reading \(areaNames)" : "Needs access to \(areaNames)"
    }

    /// The full sentence for a notice or a Detail screen.
    public var message: String {
        let items = ListFormatter.localizedString(byJoining: blocked.map(\.reason))
        if isPartial {
            let count = notMeasuredCount == 1 ? "1 item was" : "\(notMeasuredCount) items were"
            return "\(count) not measured (\(items)): \(summary.lowercasedFirst). Nothing there was read."
        }
        return "\(items) not measured: \(summary.lowercasedFirst). Nothing there was read."
    }
}

private extension String {
    var lowercasedFirst: String {
        guard let first else { return self }
        return first.lowercased() + dropFirst()
    }
}
