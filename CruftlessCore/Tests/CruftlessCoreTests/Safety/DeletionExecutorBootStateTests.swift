import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

private final class BootStateSimulatorExecutor: SimulatorCommandExecuting, @unchecked Sendable {
    private let lock = NSLock()
    private var booted: Bool
    private var entries: [String] = []

    init(booted: Bool) {
        self.booted = booted
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }

    private func record(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    private func requireShutdown(_ command: String) throws {
        lock.lock()
        let isBooted = booted
        lock.unlock()
        guard !isBooted else {
            throw NSError(
                domain: "simctl",
                code: 164,
                userInfo: [NSLocalizedDescriptionKey: "Unable to \(command) device in current state: Booted"]
            )
        }
    }

    private func markShutdown() {
        lock.lock()
        defer { lock.unlock() }
        booted = false
    }

    func shutdownSimulator(udid: String) async throws {
        record("shutdown:\(udid)")
        markShutdown()
    }

    func eraseSimulator(udid: String) async throws {
        record("erase:\(udid)")
        try requireShutdown("erase")
    }

    func deleteSimulator(udid: String) async throws {
        record("delete:\(udid)")
        try requireShutdown("delete")
    }

    func deleteRuntime(identifier: String) async throws {
        record("runtime:\(identifier)")
    }
}

@Suite("DeletionExecutor boot-state drift")
struct DeletionExecutorBootStateTests {
    @Test("A device booted after planning fails the erase instead of forcing it")
    func bootedAfterPlanningFailsClosed() async {
        let simulator = BootStateSimulatorExecutor(booted: true)
        let target = DeletionTarget.simulatorErase(
            udid: "DRIFT-1", name: "iPhone 17 Pro", isBooted: false,
            consequence: "Erase", reclaimableBytes: 8192
        )

        let result = await DeletionExecutor(simulatorExecutor: simulator).execute(DeletionPlan.single(target))

        #expect(result.failedCount == 1)
        #expect(result.totalFreedBytes == 0)
        #expect(result.items[0].status.failureReason?.contains("Booted") == true)
        #expect(simulator.commands == ["erase:DRIFT-1"])
    }

    @Test("A device shut down after planning still erases without a second shutdown")
    func shutdownAfterPlanningStillSucceeds() async {
        let simulator = BootStateSimulatorExecutor(booted: false)
        let target = DeletionTarget.simulatorErase(
            udid: "DRIFT-2", name: "iPhone 17", isBooted: true,
            consequence: "Erase", reclaimableBytes: 4096
        )

        let result = await DeletionExecutor.testExecutor(simulatorExecutor: simulator)
            .execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(simulator.commands == ["shutdown:DRIFT-2", "erase:DRIFT-2"])
    }

    @Test("A device booted after planning fails the delete too")
    func bootedAfterPlanningFailsDelete() async {
        let simulator = BootStateSimulatorExecutor(booted: true)
        let target = DeletionTarget.simulatorDelete(
            udid: "DRIFT-3", name: "iPad", isBooted: false,
            consequence: "Delete", reclaimableBytes: 1024
        )

        let result = await DeletionExecutor(simulatorExecutor: simulator).execute(DeletionPlan.single(target))

        #expect(result.failedCount == 1)
        #expect(simulator.commands == ["delete:DRIFT-3"])
    }
}
