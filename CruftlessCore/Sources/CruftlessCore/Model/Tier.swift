import Foundation

/// Defines safety and recovery characteristics of a tracked disk item.
public enum Tier: String, Sendable, Hashable, CaseIterable, Codable {
    /// Recreated automatically on next build or run.
    case regen
    /// Safe to delete, but incurs a reinstall, re-download, or simulator app data loss.
    case judgment
    /// Real, non-recoverable consequences (for example, Archives holding dSYMs).
    case irreversible
    /// Size is tracked, but deletion is handled by revealing in Finder.
    case reveal
    /// Read-only item (for example, root-owned Simulator dyld cache).
    case info

    public var isDeletable: Bool {
        switch self {
        case .regen, .judgment, .irreversible:
            true
        case .reveal, .info:
            false
        }
    }

    public var isFlagged: Bool {
        self == .irreversible
    }
}
