import CruftlessCore
import Foundation
import Testing

@Suite("DeletionExecutor stop after the current item")
struct DeletionExecutorStopTests {
    private static func erase(_ udid: String) -> DeletionTarget {
        .simulatorErase(udid: udid, name: udid, isBooted: false, consequence: "", reclaimableBytes: 512)
    }

    private static let batch: [DeletionTarget] = ["SIM-0", "SIM-1", "SIM-2", "SIM-3"].map(erase)

    @Test("A stop during an item lets it finish and skips every later item")
    func stopFinishesCurrentAndSkipsRest() async throws {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)
        let stop = DeletionStopRequest()
        let plan = try DeletionPlan.plannedBatch(Self.batch)

        let result = await executor.execute(plan, stopRequest: stop, onItemEvent: { event in
            if case .started(index: 1) = event { stop.request() }
        })

        #expect(result.items.map(\.status.isSuccess) == [true, true, false, false])
        #expect(result.succeededCount == 2)
        #expect(result.failedCount == 0)
        #expect(result.notAttemptedCount == 2)
        for item in result.items.suffix(2) {
            #expect(item.status == .notAttempted(reason: .stoppedByUser))
            #expect(item.freedBytes == 0)
        }
        #expect(mock.log.commands == ["erase:SIM-0", "erase:SIM-1"])
    }

    @Test("A stop requested before the run starts attempts nothing")
    func stopBeforeRunAttemptsNothing() async throws {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)
        let stop = DeletionStopRequest()
        stop.request()

        let result = try await executor.execute(DeletionPlan.plannedBatch(Self.batch), stopRequest: stop)

        #expect(result.notAttemptedCount == Self.batch.count)
        #expect(result.totalFreedBytes == 0)
        #expect(mock.log.commands.isEmpty)
    }

    @Test("A stop on the last item changes nothing about the run")
    func stopOnLastItemCompletesRun() async throws {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)
        let stop = DeletionStopRequest()
        let lastIndex = Self.batch.count - 1

        let result = try await executor.execute(
            DeletionPlan.plannedBatch(Self.batch),
            stopRequest: stop,
            onItemEvent: { event in
                if case let .started(index) = event, index == lastIndex { stop.request() }
            }
        )

        #expect(result.allSucceeded)
        #expect(mock.log.commands.count == Self.batch.count)
    }

    @Test("Each run carries its own stop request")
    func stopDoesNotCarryIntoNextRun() async throws {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)
        let stopped = DeletionStopRequest()
        stopped.request()

        _ = try await executor.execute(DeletionPlan.plannedBatch(Self.batch), stopRequest: stopped)
        let next = try await executor.execute(DeletionPlan.plannedBatch(Self.batch), stopRequest: DeletionStopRequest())

        #expect(next.allSucceeded)
    }

    @Test("Run state marks stopped items as skipped with the stop copy")
    func runStateShowsStoppedItems() async throws {
        let plan = try DeletionPlan.plannedBatch(Self.batch)
        var run = DeletionRunState(plan: plan)
        #expect(run.hasPendingItems)

        let executor = DeletionExecutor.testExecutor(simulatorExecutor: MockSimulatorExecutor())
        let stop = DeletionStopRequest()
        let result = await executor.execute(plan, stopRequest: stop, onItemEvent: { event in
            if case .started(index: 0) = event { stop.request() }
        })
        run.settle(with: result)

        #expect(!run.hasPendingItems)
        #expect(run.state(for: Self.batch[3].id) == .skipped(reason: NotAttemptedReason.stoppedByUser.copy))
    }
}
