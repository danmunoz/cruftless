import Foundation

public struct RootPreferenceIssue: Sendable, Hashable {
    /// The specific rule the configured value tripped.
    public enum Reason: String, Sendable, Hashable, CaseIterable {
        /// Not absolute after tilde expansion.
        case notAbsolute
        /// The filesystem root itself.
        case filesystemRoot
        /// Equal to, or an ancestor of, the user's home folder.
        case containsHomeFolder
        /// On the protected denylist, or containing something that is.
        case protectedLocation
        /// Overlaps the root of another location Cruftless already tracks.
        case overlapsTrackedLocation

        var clause: String {
            switch self {
            case .notAbsolute:
                "it is not an absolute path."
            case .filesystemRoot:
                "it is the root of the filesystem."
            case .containsHomeFolder:
                "it contains your home folder."
            case .protectedLocation:
                "it is a protected location, or holds one."
            case .overlapsTrackedLocation:
                "it overlaps another location Cruftless tracks."
            }
        }
    }

    /// The Xcode user-default key the value came from.
    public let preferenceKey: String
    /// The value as configured, before any expansion.
    public let value: String
    public let reason: Reason

    public init(preferenceKey: String, value: String, reason: Reason) {
        self.preferenceKey = preferenceKey
        self.value = value
        self.reason = reason
    }

    /// User-facing copy, ready to show in Settings or an inspector row.
    public var message: String {
        "Xcode's \(preferenceKey) setting (\(value)) was ignored because \(reason.clause) "
            + "Cruftless is using its default location instead."
    }
}
