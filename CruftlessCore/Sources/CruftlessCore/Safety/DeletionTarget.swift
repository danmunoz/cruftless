import Foundation

/// A condition the executor re-checks immediately before deleting a path.
public enum DeletionPrecondition: Sendable, Hashable {
    /// The simulator that owns this path must still be shut down.
    case simulatorShutdown(devicePlist: URL, deviceName: String)
}

/// Represents a distinct target to be deleted or mutated.
public enum DeletionTarget: Sendable, Hashable, Identifiable {
    case path(
        id: String,
        name: String,
        validatedPath: ValidatedPath,
        fingerprint: Fingerprint,
        tier: Tier,
        consequence: String,
        reclaimableBytes: Int64,
        precondition: DeletionPrecondition? = nil
    )
    case simulatorErase(
        udid: String,
        name: String,
        isBooted: Bool,
        consequence: String,
        reclaimableBytes: Int64
    )
    case simulatorDelete(
        udid: String,
        name: String,
        isBooted: Bool,
        consequence: String,
        reclaimableBytes: Int64
    )
    case runtimeDelete(
        identifier: String,
        name: String,
        consequence: String,
        reclaimableBytes: Int64
    )

    public var id: String {
        switch self {
        case let .path(id, _, _, _, _, _, _, _):
            id
        case let .simulatorErase(udid, _, _, _, _):
            "sim-erase-\(udid)"
        case let .simulatorDelete(udid, _, _, _, _):
            "sim-delete-\(udid)"
        case let .runtimeDelete(identifier, _, _, _):
            "runtime-\(identifier)"
        }
    }

    public var name: String {
        switch self {
        case let .path(_, name, _, _, _, _, _, _):
            name
        case let .simulatorErase(_, name, _, _, _),
             let .simulatorDelete(_, name, _, _, _),
             let .runtimeDelete(_, name, _, _):
            name
        }
    }

    public var tier: Tier {
        switch self {
        case let .path(_, _, _, _, tier, _, _, _):
            tier
        case .simulatorErase, .simulatorDelete, .runtimeDelete:
            .judgment
        }
    }

    public var consequence: String {
        switch self {
        case let .path(_, _, _, _, _, consequence, _, _):
            consequence
        case let .simulatorErase(_, _, _, consequence, _),
             let .simulatorDelete(_, _, _, consequence, _),
             let .runtimeDelete(_, _, consequence, _):
            consequence
        }
    }

    public var reclaimableBytes: Int64 {
        switch self {
        case let .path(_, _, _, _, _, _, bytes, _),
             let .simulatorErase(_, _, _, _, bytes),
             let .simulatorDelete(_, _, _, _, bytes),
             let .runtimeDelete(_, _, _, bytes):
            bytes
        }
    }

    /// The guard's receipt for a path target, or `nil` for a `simctl` target.
    public var validatedPath: ValidatedPath? {
        if case let .path(_, _, validatedPath, _, _, _, _, _) = self {
            return validatedPath
        }
        return nil
    }

    public var precondition: DeletionPrecondition? {
        if case let .path(_, _, _, _, _, _, _, precondition) = self {
            return precondition
        }
        return nil
    }

    public var isFlagged: Bool {
        tier.isFlagged
    }
}
