import Foundation

/// The lifecycle state CoreSimulator reports for an installed runtime image: `simctl runtime list -j`'s `state` field.
public enum SimRuntimeState: Sendable, Hashable {
    /// Installed and usable.
    case ready
    /// CoreSimulator has accepted a delete for this runtime and is still carrying it out.
    case deleting
    /// Present but not usable: an unverified or damaged image.
    case unusable
    /// A state string this app does not model.
    case other(String)
    /// The source that produced this runtime reports no state at all.
    case unreported

    /// Maps `simctl`'s `state` string.
    public init(simctlValue: String?) {
        switch simctlValue?.lowercased() {
        case nil: self = .unreported
        case "ready": self = .ready
        case "deleting": self = .deleting
        case "unusable": self = .unusable
        case let other?: self = .other(other)
        }
    }

    /// True only for a runtime CoreSimulator is actively removing.
    public var isBeingDeleted: Bool {
        self == .deleting
    }
}
