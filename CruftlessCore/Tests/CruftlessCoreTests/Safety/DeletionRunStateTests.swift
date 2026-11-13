import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("Deletion run state")
struct DeletionRunStateTests {
    private final class EventLog: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: [DeletionItemEvent] = []
        func append(_ event: DeletionItemEvent) {
            lock.withLock { stored.append(event) }
        }

        var values: [DeletionItemEvent] {
            lock.withLock { stored }
        }
    }

    /// A path target whose file is removed after capture when `vanishes` is set, so executing it fails.
    private static func pathTarget(_ name: String, in base: URL, vanishes: Bool = false) throws -> DeletionTarget {
        let file = base.appendingPathComponent(name)
        try "data".write(to: file, atomically: true, encoding: .utf8)
        let validated = try PathGuard(roots: [base]).validate(file)
        let fingerprint = try #require(Fingerprint.capture(at: file))
        if vanishes { TestFileSystem.removeDirectoryRecursively(at: file) }
        return .path(
            id: name, name: name, validatedPath: validated, fingerprint: fingerprint,
            tier: .regen, consequence: "Rebuilt", reclaimableBytes: 4
        )
    }

    @Test("A failing item does not stop the batch and every item reports start and finish in order")
    func failureDoesNotStopTheBatch() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let targets = try [
            Self.pathTarget("first", in: base),
            Self.pathTarget("missing", in: base, vanishes: true),
            Self.pathTarget("third", in: base)
        ]
        let plan = DeletionPlan.plannedBatch(targets)
        let log = EventLog()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: MockSimulatorExecutor())

        let result = await executor.execute(plan, onItemEvent: { log.append($0) })

        #expect(result.items.map(\.status.isSuccess) == [true, false, true])
        let kinds = log.values.map { event -> String in
            switch event {
            case let .started(index): "start\(index)"
            case let .finished(index, _): "finish\(index)"
            }
        }
        #expect(kinds == ["start0", "finish0", "start1", "finish1", "start2", "finish2"])

        var run = DeletionRunState(plan: plan)
        #expect(run.finishedCount == 0)
        for event in log.values {
            run.apply(event)
        }
        #expect(run.finishedCount == 3)
        guard case .failed = run.state(for: "missing") else {
            Issue.record("The missing item must be failed")
            return
        }
        guard case .done = run.state(for: "third") else {
            Issue.record("The item after a failure must still complete")
            return
        }
    }

    @Test("Position and active item follow the events")
    func positionFollowsEvents() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let plan = try DeletionPlan.plannedBatch([
            Self.pathTarget("a", in: base),
            Self.pathTarget("b", in: base)
        ])
        var run = DeletionRunState(plan: plan)
        #expect(run.currentPosition == 1)
        run.apply(.started(index: 0))
        #expect(run.activeID == "a")
        run.apply(.finished(index: 0, outcome: ItemOutcome(target: plan.items[0], status: .succeeded, freedBytes: 4)))
        #expect(run.activeID == nil)
        #expect(run.currentPosition == 2)
        run.apply(.started(index: 1))
        #expect(run.activeID == "b")
        #expect(run.total == 2)
    }

    @Test("Settling from a result marks never-reported items")
    func settleCoversRefusedRuns() throws {
        let base = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let plan = try DeletionPlan.plannedBatch([Self.pathTarget("a", in: base)])
        var run = DeletionRunState(plan: plan)
        let skipped = ItemOutcome(target: plan.items[0], status: .notAttempted(reason: .policyChanged), freedBytes: 0)
        run.settle(with: DeletionResult(items: [skipped]))
        guard case .skipped = run.state(for: "a") else {
            Issue.record("A refused run must settle items as skipped")
            return
        }
    }
}
