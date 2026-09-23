import CruftlessCore
import Foundation

final class CommandLog: @unchecked Sendable {
    private let lock = NSLock()
    private var entries: [String] = []

    func record(_ entry: String) {
        lock.lock()
        defer { lock.unlock() }
        entries.append(entry)
    }

    var commands: [String] {
        lock.lock()
        defer { lock.unlock() }
        return entries
    }
}

struct MockSimulatorExecutor: SimulatorCommandExecuting {
    var shouldFailErase = false
    var shouldFailDelete = false
    var shouldFailRuntime = false
    var shouldFailShutdown = false
    var log = CommandLog()

    func shutdownSimulator(udid: String) async throws {
        log.record("shutdown:\(udid)")
        if shouldFailShutdown {
            throw NSError(domain: "MockSim", code: 4, userInfo: [NSLocalizedDescriptionKey: "Shutdown failed"])
        }
    }

    func eraseSimulator(udid: String) async throws {
        log.record("erase:\(udid)")
        if shouldFailErase {
            throw NSError(domain: "MockSim", code: 1, userInfo: [NSLocalizedDescriptionKey: "Erase failed"])
        }
    }

    func deleteSimulator(udid: String) async throws {
        log.record("delete:\(udid)")
        if shouldFailDelete {
            throw NSError(domain: "MockSim", code: 2, userInfo: [NSLocalizedDescriptionKey: "Delete simulator failed"])
        }
    }

    func deleteRuntime(identifier: String) async throws {
        log.record("runtime:\(identifier)")
        if shouldFailRuntime {
            throw NSError(domain: "MockSim", code: 3, userInfo: [NSLocalizedDescriptionKey: "Delete runtime failed"])
        }
    }
}

final class ScriptedCapacity: @unchecked Sendable {
    private let lock = NSLock()
    private let readings: [Int64]
    private var index = 0

    init(_ readings: [Int64]) {
        self.readings = readings
    }

    /// Returns the next reading, repeating the final value.
    func next() -> Int64 {
        lock.lock()
        defer { lock.unlock() }
        let value = readings[min(index, readings.count - 1)]
        index += 1
        return value
    }

    var samplesTaken: Int {
        lock.lock()
        defer { lock.unlock() }
        return index
    }
}

final class ProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [DeletionProgress] = []

    func record(_ event: DeletionProgress) {
        lock.lock()
        defer { lock.unlock() }
        events.append(event)
    }

    var values: [DeletionProgress] {
        lock.lock()
        defer { lock.unlock() }
        return events
    }
}

final class SleepCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var sleeps = 0

    /// Records a sleep call.
    func tick() {
        lock.lock()
        defer { lock.unlock() }
        sleeps += 1
    }

    var count: Int {
        lock.lock()
        defer { lock.unlock() }
        return sleeps
    }

    /// True when no sleep was recorded.
    var isEmpty: Bool {
        lock.lock()
        defer { lock.unlock() }
        return sleeps == 0
    }
}

extension DeletionExecutor {
    /// Creates instant, disk-free settling seams.
    static func testExecutor(
        simulatorExecutor: SimulatorCommandExecuting,
        deviceDirectory: @escaping @Sendable (String) -> URL? = { _ in nil },
        capacitySampler: @escaping @Sendable () async -> Int64 = { 0 },
        settleSleep: @escaping @Sendable () async throws -> Void = {}
    ) -> DeletionExecutor {
        DeletionExecutor(
            simulatorExecutor: simulatorExecutor,
            capacitySampler: capacitySampler,
            deviceDirectory: deviceDirectory,
            settleSleep: settleSleep
        )
    }
}
