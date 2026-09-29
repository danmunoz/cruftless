import Foundation

/// Synchronously serializes policy changes with deletion admission.
public final class PolicyGenerationAuthority: @unchecked Sendable {
    private let lock = NSLock()
    private var generation: UInt64
    private var readOnlyLocationIDs: Set<String> = []

    public init(initialGeneration: UInt64 = 0) {
        generation = initialGeneration
    }

    public var currentGeneration: UInt64 {
        lock.lock()
        defer { lock.unlock() }
        return generation
    }

    public func update(to nextGeneration: UInt64, readOnlyLocationIDs: Set<String> = []) {
        lock.lock()
        defer { lock.unlock() }
        guard nextGeneration >= generation else { return }
        generation = nextGeneration
        self.readOnlyLocationIDs = readOnlyLocationIDs
    }

    public func readOnlyLocationIDs(matching targets: [DeletionTarget]) -> Set<String> {
        lock.lock()
        defer { lock.unlock() }
        return Set(readOnlyLocationIDs.filter { locationID in
            targets.contains { $0.id.hasPrefix(locationID + "-") }
        })
    }

    /// Runs admission while a matching policy generation cannot be replaced.
    public func withCurrentGeneration<Result>(
        _ expectedGeneration: UInt64,
        affectedLocationIDs: Set<String> = [],
        admission: () -> Result
    ) -> Result? {
        lock.lock()
        defer { lock.unlock() }
        guard generation == expectedGeneration,
              affectedLocationIDs.isDisjoint(with: readOnlyLocationIDs)
        else { return nil }
        return admission()
    }
}
