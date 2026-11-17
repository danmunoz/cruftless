import Dispatch
import Foundation
import Synchronization

/// What macOS answered for one area, and which locations that answer changes.
public struct AccessAnswer: Sendable, Hashable {
    public let area: ProtectedArea
    public let outcome: AccessRequestOutcome
    public let locationIds: Set<String>

    public init(area: ProtectedArea, outcome: AccessRequestOutcome, locationIds: Set<String>) {
        self.area = area
        self.outcome = outcome
        self.locationIds = locationIds
    }
}

/// Loads the access list and asks macOS about one area, both off the caller's thread.
public struct AccessService: Sendable {
    public typealias Load = @Sendable ([TrackedLocation]) async -> [AccessAreaSummary]
    public typealias Request = @Sendable (AccessAreaSummary) async throws -> AccessRequestOutcome

    public let load: Load
    public let request: Request

    public init(load: @escaping Load, request: @escaping Request) {
        self.load = load
        self.request = request
    }

    /// The service the app runs with; every list in the process shares its one request slot.
    public static let live = AccessService.standard()

    /// A service over `gate`, allowing one request in flight at a time across every caller sharing it.
    public static func standard(
        gate: AccessGate = .shared,
        opener: @escaping AccessRequest.Opener = AccessRequest.openDirectory,
        preflight: @escaping @Sendable ([TrackedLocation], AccessGate) async -> [AreaAccessNeed] = { catalog, gate in
            await AccessPreflight.needs(catalog: catalog, gate: gate)
        }
    ) -> AccessService {
        let slot = RequestSlot()
        let accessRequest = AccessRequest(gate: gate, opener: opener)
        return AccessService(
            load: { catalog in
                let needs = await preflight(catalog, gate)
                return await offThread { AccessOverview.areas(needs: needs, gate: gate, opener: opener) }
            },
            request: { summary in
                guard slot.claim() else { throw AccessRequestError.requestInFlight }
                defer { slot.release() }
                let path = summary.reasons.first?.path ?? gate.classifier.defaultRoot(for: summary.area)
                guard let path else { throw AccessRequestError.pathOutsideArea }
                return try await offThread { try accessRequest.request(area: summary.area, path: path) }
            }
        )
    }

    /// Runs blocking work on a dispatch queue, since an open waits for as long as macOS's alert is on screen.
    private static func offThread<T: Sendable>(_ work: @escaping @Sendable () throws -> T) async throws -> T {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(with: Result { try work() })
            }
        }
    }

    private static func offThread<T: Sendable>(_ work: @escaping @Sendable () -> T) async -> T {
        await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                continuation.resume(returning: work())
            }
        }
    }
}

/// Admits one request at a time.
private final class RequestSlot: Sendable {
    private let isBusy = Mutex(false)

    func claim() -> Bool {
        isBusy.withLock { busy in
            guard !busy else { return false }
            busy = true
            return true
        }
    }

    func release() {
        isBusy.withLock { $0 = false }
    }
}
