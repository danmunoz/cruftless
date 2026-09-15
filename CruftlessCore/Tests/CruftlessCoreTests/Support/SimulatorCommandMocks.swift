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
