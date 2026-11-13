import Foundation

/// Who asked for a scan.
public enum ScanTrigger: Sendable, Equatable {
    /// Launch, the Refresh button, a settings change, the rescan after a deletion: a scan someone is waiting for.
    case user
    /// An FSEvents invalidation.
    case background
}

/// One scan: what it covers and who asked for it.
public struct ScanRequest: Sendable, Equatable {
    public var scope: InvalidationScope
    public var trigger: ScanTrigger

    public init(scope: InvalidationScope, trigger: ScanTrigger) {
        self.scope = scope
        self.trigger = trigger
    }
}

/// The app state that decides whether a background scan may run now.
public struct ScanConditions: Sendable, Equatable {
    /// False until the session's first scan starts, which walks everything after any earlier event.
    public var hasStartedInitialScan: Bool
    /// True while a deletion runs, so no background walk races it.
    public var isDeleting: Bool

    public init(hasStartedInitialScan: Bool, isDeleting: Bool) {
        self.hasStartedInitialScan = hasStartedInitialScan
        self.isDeleting = isDeleting
    }
}

/// Decides when each scan runs: one at a time, background requests throttled and held back before the first scan and during a deletion.
public struct ScanScheduler: Sendable {
    public enum Admission: Sendable, Equatable {
        /// Run this now.
        case start(ScanRequest)
        /// Waiting behind the running scan or a deletion.
        case queued(ScanRequest)
        /// Nothing to run: no first scan yet, or every location is inside its quiet period.
        case declined
    }

    /// The scan that is running, or nil when none is.
    public private(set) var active: ScanRequest?

    /// Work waiting for the running scan or a deletion to end, merged into one request.
    public private(set) var pending: ScanRequest?

    private let throttleInterval: TimeInterval
    private var throttle: RescanThrottle

    public init(
        throttleInterval: TimeInterval = RescanThrottle.defaultInterval,
        active: ScanRequest? = nil
    ) {
        self.throttleInterval = throttleInterval
        throttle = RescanThrottle(interval: throttleInterval)
        self.active = active
    }

    /// When the earliest throttled location becomes eligible, or nil when nothing is held.
    public var nextWake: Date? {
        throttle.nextWake
    }

    /// Admits one request: starts it, queues it, or declines it.
    public mutating func request(
        _ request: ScanRequest,
        at now: Date,
        catalog: Set<String>,
        conditions: ScanConditions
    ) -> Admission {
        var request = request
        if request.trigger == .background {
            guard conditions.hasStartedInitialScan else { return .declined }
            guard let admitted = throttle.admit(request.scope, at: now, catalog: Array(catalog)) else {
                return .declined
            }
            request.scope = admitted
            if conditions.isDeleting {
                enqueue(request)
                return .queued(request)
            }
        }

        guard active == nil else {
            enqueue(request)
            if request.trigger == .user { active?.trigger = .user }
            return .queued(request)
        }
        active = request
        return .start(request)
    }

    /// Ends the running scan; a completed one starts the quiet period for what it walked, an abandoned one (nil) records nothing.
    public mutating func complete(walked: Set<String>?, at now: Date) {
        active = nil
        if let walked {
            throttle.recordCompletion(of: walked, at: now)
        }
    }

    /// Re-admits queued work once nothing is running.
    public mutating func resume(
        at now: Date,
        catalog: Set<String>,
        conditions: ScanConditions
    ) -> Admission? {
        guard active == nil, let queued = pending else { return nil }
        pending = nil
        return request(queued, at: now, catalog: catalog, conditions: conditions)
    }

    /// The throttled locations whose quiet period has ended.
    public mutating func releaseDue(at now: Date) -> InvalidationScope? {
        throttle.release(at: now)
    }

    /// Whether the running or queued work will measure this location.
    public func covers(_ locationId: String, catalog: Set<String>) -> Bool {
        [active, pending].contains { request in
            switch request?.scope {
            case nil: false
            case .everything: catalog.contains(locationId)
            case let .locations(ids): ids.contains(locationId)
            }
        }
    }

    /// Forgets queued work and quiet periods; the running scan keeps running.
    public mutating func reset() {
        pending = nil
        throttle = RescanThrottle(interval: throttleInterval)
    }

    private mutating func enqueue(_ request: ScanRequest) {
        guard let queued = pending else {
            pending = request
            return
        }
        pending = ScanRequest(
            scope: queued.scope.merged(with: request.scope),
            trigger: queued.trigger == .user || request.trigger == .user ? .user : .background
        )
    }
}
