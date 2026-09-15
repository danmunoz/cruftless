import Foundation

/// A minimum gap between two *automatic* rescans of the same location.
public struct RescanThrottle: Sendable {
    public static let defaultInterval: TimeInterval = 60

    private let interval: TimeInterval

    /// When each location was last walked, whoever asked for the walk.
    private var lastCompleted: [String: Date] = [:]

    /// Locations whose automatic rescan is waiting out a quiet period, and when each becomes eligible.
    private var heldUntil: [String: Date] = [:]

    public init(interval: TimeInterval = RescanThrottle.defaultInterval) {
        self.interval = interval
    }

    /// Starts the quiet period for every location a finished scan walked.
    public mutating func recordCompletion(of ids: some Sequence<String>, at now: Date) {
        for id in ids {
            lastCompleted[id] = now
        }
    }

    /// The part of `scope` that may be scanned now, or nil when all of it is still inside a quiet period.
    public mutating func admit(
        _ scope: InvalidationScope,
        at now: Date,
        catalog: [String]
    ) -> InvalidationScope? {
        let requested: Set<String> = switch scope {
        case .everything: Set(catalog)
        case let .locations(ids): ids
        }

        var admitted: Set<String> = []
        for id in requested {
            if let last = lastCompleted[id], now.timeIntervalSince(last) < interval {
                heldUntil[id] = last.addingTimeInterval(interval)
            } else {
                admitted.insert(id)
                heldUntil[id] = nil
            }
        }

        guard !admitted.isEmpty else { return nil }

        if case .everything = scope, admitted.count == requested.count {
            return .everything
        }
        return .locations(admitted)
    }

    /// The held locations whose quiet period has ended, cleared as they are handed back.
    public mutating func release(at now: Date) -> InvalidationScope? {
        let due = Set(heldUntil.filter { $0.value <= now }.keys)
        guard !due.isEmpty else { return nil }
        for id in due {
            heldUntil[id] = nil
        }
        return .locations(due)
    }

    /// When the earliest held location becomes eligible, or nil when nothing is being held.
    public var nextWake: Date? {
        heldUntil.values.min()
    }
}
