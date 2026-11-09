import Foundation

/// A per-item event emitted while a plan executes.
public enum DeletionItemEvent: Sendable, Equatable {
    case started(index: Int)
    case finished(index: Int, outcome: ItemOutcome)
}

/// Where one plan item stands during a run.
public enum DeletionItemRunState: Sendable, Equatable {
    case pending
    case active
    case done(freedBytes: Int64)
    case failed(reason: String)
    case skipped(reason: String)
}

/// Live state of a running plan, driven by `DeletionItemEvent`s.
public struct DeletionRunState: Sendable, Equatable {
    public let itemIDs: [String]
    public private(set) var states: [DeletionItemRunState]

    public init(plan: DeletionPlan) {
        itemIDs = plan.items.map(\.id)
        states = Array(repeating: .pending, count: plan.items.count)
    }

    public var total: Int {
        itemIDs.count
    }

    /// Items that reached a final state.
    public var finishedCount: Int {
        states.count { state in
            switch state {
            case .pending, .active: false
            case .done, .failed, .skipped: true
            }
        }
    }

    public var activeID: String? {
        states.firstIndex(of: .active).map { itemIDs[$0] }
    }

    /// The 1-based position of the active item, or the next pending one.
    public var currentPosition: Int {
        if let index = states.firstIndex(of: .active) { return index + 1 }
        return min(finishedCount + 1, max(total, 1))
    }

    public func state(for itemID: String) -> DeletionItemRunState {
        itemIDs.firstIndex(of: itemID).map { states[$0] } ?? .pending
    }

    public mutating func apply(_ event: DeletionItemEvent) {
        switch event {
        case let .started(index):
            guard states.indices.contains(index) else { return }
            states[index] = .active
        case let .finished(index, outcome):
            guard states.indices.contains(index) else { return }
            states[index] = Self.state(for: outcome)
        }
    }

    /// Settles every item from a finished result, covering runs that refused before emitting events.
    public mutating func settle(with result: DeletionResult) {
        for (index, outcome) in result.items.enumerated() where states.indices.contains(index) {
            states[index] = Self.state(for: outcome)
        }
    }

    static func state(for outcome: ItemOutcome) -> DeletionItemRunState {
        switch outcome.status {
        case .succeeded: .done(freedBytes: outcome.freedBytes)
        case let .failed(reason), let .partiallyFailed(reason): .failed(reason: reason)
        case let .notAttempted(reason): .skipped(reason: reason.copy)
        }
    }
}
