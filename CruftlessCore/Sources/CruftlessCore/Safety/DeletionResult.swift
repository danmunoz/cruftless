import Foundation

public enum NotAttemptedReason: Sendable, Hashable {
    /// The run was cancelled before execution reached this item.
    case cancelled
    case executorBusy

    /// User-facing copy for this reason.
    public var copy: String {
        switch self {
        case .cancelled:
            "Not attempted: the operation was cancelled."
        case .executorBusy:
            "Not attempted: another deletion is already running."
        }
    }
}

public enum ItemOutcomeStatus: Sendable, Hashable {
    case succeeded
    case failed(reason: String)
    /// Some of the target came off disk and some did not.
    case partiallyFailed(reason: String)
    /// Nothing was tried on this item, so nothing changed on disk.
    case notAttempted(reason: NotAttemptedReason)

    /// Only a complete delete is a success; a partial one is not.
    public var isSuccess: Bool {
        if case .succeeded = self { return true }
        return false
    }

    /// True only for `partiallyFailed`.
    public var isPartialFailure: Bool {
        if case .partiallyFailed = self { return true }
        return false
    }

    /// True only for `.notAttempted`: an item the run never reached, as opposed to one it reached and failed on.
    public var isNotAttempted: Bool {
        if case .notAttempted = self { return true }
        return false
    }

    /// `nil` for `.notAttempted`: it is not a failure, so it carries no failure reason.
    public var failureReason: String? {
        switch self {
        case .succeeded, .notAttempted:
            nil
        case let .failed(reason), let .partiallyFailed(reason):
            reason
        }
    }

    public var notAttemptedReason: String? {
        guard case let .notAttempted(reason) = self else { return nil }
        return reason.copy
    }
}

public struct ItemOutcome: Sendable, Hashable, Identifiable {
    public var id: String {
        target.id
    }

    public let target: DeletionTarget
    public let status: ItemOutcomeStatus
    public let freedBytes: Int64
    /// Space-settle outcome for a successful simctl target.
    public let spaceSettle: SpaceSettleOutcome?

    public init(
        target: DeletionTarget,
        status: ItemOutcomeStatus,
        freedBytes: Int64,
        spaceSettle: SpaceSettleOutcome? = nil
    ) {
        self.target = target
        self.status = status
        self.freedBytes = freedBytes
        self.spaceSettle = spaceSettle
    }
}

/// The immutable outcome of executing a `DeletionPlan`.
public struct DeletionResult: Sendable, Hashable {
    public let items: [ItemOutcome]

    /// Bytes that actually came off disk, including the part a partially failed item did manage to remove.
    public var totalFreedBytes: Int64 {
        items.reduce(0) { sum, item in
            item.status.isSuccess || item.status.isPartialFailure ? sum + item.freedBytes : sum
        }
    }

    public var succeededCount: Int {
        items.count(where: { $0.status.isSuccess })
    }

    /// Items that came off disk in part.
    public var partiallyFailedCount: Int {
        items.count(where: { $0.status.isPartialFailure })
    }

    /// Items that came off disk not at all.
    public var failedCount: Int {
        items.count(where: {
            !$0.status.isSuccess && !$0.status.isPartialFailure && !$0.status.isNotAttempted
        })
    }

    /// Items nothing was tried on: the run was cancelled before reaching them, or the executor was already busy.
    public var notAttemptedCount: Int {
        items.count(where: { $0.status.isNotAttempted })
    }

    /// Anything that did not come off disk whole.
    public var hasFailures: Bool {
        failedCount > 0 || partiallyFailedCount > 0
    }

    public var allSucceeded: Bool {
        !items.isEmpty && succeededCount == items.count
    }

    public init(items: [ItemOutcome]) {
        self.items = items
    }
}
