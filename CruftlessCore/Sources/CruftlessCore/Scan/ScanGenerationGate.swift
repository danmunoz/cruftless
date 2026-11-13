import Synchronization

/// The scan generation, shared between the engine actor and the walks it queues.
final class ScanGenerationGate: Sendable {
    private let value = Atomic<UInt64>(0)

    var current: UInt64 {
        get { value.load(ordering: .acquiring) }
        set { value.store(newValue, ordering: .releasing) }
    }
}
