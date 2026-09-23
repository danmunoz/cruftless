import Foundation

/// Progress reported by a deletion run.
public struct DeletionProgress: Sendable, Equatable {
    public enum Verb: Sendable, Equatable {
        case erase
        case delete
        case clear
        case remove
    }

    public enum Phase: Sendable, Equatable {
        /// The target is being mutated or confirmed.
        case mutating
        /// The mutation is confirmed while free space settles.
        case waitingForSpace

        /// Secondary status text for the active phase.
        public var detail: String? {
            switch self {
            case .mutating: nil
            case .waitingForSpace: "freeing space, this can take a minute"
            }
        }
    }

    public let verb: Verb
    public let targetName: String
    public let phase: Phase

    public init(verb: Verb, targetName: String, phase: Phase) {
        self.verb = verb
        self.targetName = targetName
        self.phase = phase
    }

    /// User-facing progress label.
    public var label: String {
        let word = switch verb {
        case .erase: "Erasing"
        case .delete: "Deleting"
        case .clear: "Clearing"
        case .remove: "Removing"
        }
        return "\(word) \(targetName)…"
    }
}
