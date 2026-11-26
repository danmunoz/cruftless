import Synchronization

/// A user's request to finish the item in progress and skip the rest of one run.
public final class DeletionStopRequest: Sendable {
    private let requested = Atomic<Bool>(false)

    public init() {}

    /// Marks the run as stopping; the executor checks it before starting each item.
    public func request() {
        requested.store(true, ordering: .sequentiallyConsistent)
    }

    public var isRequested: Bool {
        requested.load(ordering: .sequentiallyConsistent)
    }
}
