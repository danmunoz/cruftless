import CruftlessCore
import Foundation
import Synchronization

/// Holds `ScanEngine.walkQueue` until released, and releases it on its own after `failsafe` so a test cannot wedge the queue.
final class WalkQueueHold: Sendable {
    private let semaphore = DispatchSemaphore(value: 0)
    private let state = Mutex<(held: Bool, releasedByFailsafe: Bool)>((true, false))

    init(failsafe: Duration = .seconds(30)) {
        let semaphore = semaphore
        ScanEngine.walkQueue.async { semaphore.wait() }
        Task { [weak self] in
            try? await Task.sleep(for: failsafe)
            self?.release(byFailsafe: true)
        }
    }

    var isHeld: Bool { state.withLock { $0.held } }
    var releasedByFailsafe: Bool { state.withLock { $0.releasedByFailsafe } }

    func release() { release(byFailsafe: false) }

    private func release(byFailsafe: Bool) {
        let wasHeld = state.withLock { state in
            guard state.held else { return false }
            state = (false, byFailsafe)
            return true
        }
        if wasHeld { semaphore.signal() }
    }
}

/// A one-shot latch an injected async dependency waits on, opened by the test or by `failsafe`.
final class AsyncLatch: Sendable {
    private let stream: AsyncStream<Void>
    private let continuation: AsyncStream<Void>.Continuation
    private let state = Mutex<(open: Bool, openedByFailsafe: Bool)>((false, false))

    init(failsafe: Duration = .seconds(30)) {
        (stream, continuation) = AsyncStream.makeStream(of: Void.self)
        Task { [weak self] in
            try? await Task.sleep(for: failsafe)
            self?.open(byFailsafe: true)
        }
    }

    var openedByFailsafe: Bool { state.withLock { $0.openedByFailsafe } }

    func open() { open(byFailsafe: false) }

    func wait() async {
        for await _ in stream { return }
    }

    private func open(byFailsafe: Bool) {
        let wasClosed = state.withLock { state in
            guard !state.open else { return false }
            state = (true, byFailsafe)
            return true
        }
        if wasClosed { continuation.finish() }
    }
}
