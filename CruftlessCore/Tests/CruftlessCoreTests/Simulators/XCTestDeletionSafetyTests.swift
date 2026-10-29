@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("XCTest cleanup safety")
struct XCTestDeletionSafetyTests {
    @Test("Only scoped deletion can remove a retained test device")
    func scopedDeletionPreservesOrdinaryDevice() async throws {
        let fixture = try Fixture(ordinaryTwin: true)
        defer { fixture.remove() }
        let commands = ScopedCommands(directory: fixture.directory, removesDevice: true)
        let plan = try DeletionPlanner.xctestSimulatorDelete(for: fixture.device(), size: 1, context: PlanningContext())
        let executor = DeletionExecutor(
            simulatorExecutor: commands,
            capacitySampler: { 100 },
            settleSleep: {},
            xctestConfirmationTimeout: .milliseconds(10)
        )
        let result = await executor.execute(plan)
        #expect(result.allSucceeded)
        #expect(commands.log.commands == ["xctest:\(fixture.udid)"])
        #expect(FileManager.default.fileExists(atPath: fixture.ordinaryDirectory.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Booted or unknown test devices cannot reach Review", arguments: [SimDeviceState.booted, .other])
    func planningRejectsNonShutdown(state: SimDeviceState) throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.xctestSimulatorDelete(for: fixture.device(state: state), size: 1, context: PlanningContext())
        }
    }

    @Test("Unknown runtime authority blocks the direct test-device planner")
    func unknownRuntimeRefuses() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let device = fixture.device().markingRuntimeAvailability(.unknown("lookup failed"))
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.xctestSimulatorDelete(for: device, size: 1, context: PlanningContext())
        }
    }

    @Test("Ordinary erase, delete and raw bloat planners refuse test devices")
    func ordinaryPlannersRefuseTestDevices() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let device = fixture.device()
        #expect(throws: DeletionPlanningError.self) { try DeletionPlanner.simulatorErase(for: device, context: PlanningContext()) }
        #expect(throws: DeletionPlanningError.self) { try DeletionPlanner.simulatorDelete(for: device, context: PlanningContext()) }
        #expect(throws: DeletionPlanningError.self) { try DeletionPlanner.simulatorBloat(for: device, context: PlanningContext()) }
        #expect(throws: DeletionPlanningError.self) { try KnownBloat.createBloatDeletionPlan(for: device) }
    }

    @Test("State or identity changed during capacity sampling refuses before simctl", arguments: [false, true])
    func changedAfterAwait(replaceDirectory: Bool) async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let plan = try DeletionPlanner.xctestSimulatorDelete(for: fixture.device(), size: 1, context: PlanningContext())
        let commands = ScopedCommands(directory: fixture.directory)
        let executor = DeletionExecutor(simulatorExecutor: commands, capacitySampler: {
            if replaceDirectory {
                TestFileSystem.removeDirectoryRecursively(at: fixture.directory)
                try? fixture.createOwnedDirectory(fixture.directory)
            }
            try? fixture.writePlist(state: replaceDirectory ? .shutdown : .booted)
            return 0
        }, settleSleep: {})
        let result = await executor.execute(plan)
        #expect(result.failedCount == 1)
        #expect(commands.log.commands.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("A protection added during capacity sampling refuses before simctl")
    func protectionChangedAfterAwait() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let defaults = try #require(UserDefaults(suiteName: UUID().uuidString))
        let store = ProtectedPathsStore(userDefaults: defaults)
        let plan = try DeletionPlanner.xctestSimulatorDelete(for: fixture.device(), size: 1, context: PlanningContext())
        let commands = ScopedCommands(directory: fixture.directory)
        let executor = DeletionExecutor(simulatorExecutor: commands, protectedPathsStore: store, capacitySampler: {
            store.addPath(fixture.directory.appendingPathComponent("data/keep"))
            return 0
        }, settleSleep: {})
        let result = await executor.execute(plan)
        #expect(result.failedCount == 1)
        #expect(commands.log.commands.isEmpty)
    }

    @Test("Accepted command with a retained directory never claims freed bytes")
    func unconfirmedRemovalRefuses() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let commands = ScopedCommands(directory: fixture.directory)
        let plan = try DeletionPlanner.xctestSimulatorDelete(for: fixture.device(), size: 4000, context: PlanningContext())
        let executor = DeletionExecutor(
            simulatorExecutor: commands,
            capacitySampler: { 0 },
            settleSleep: {},
            xctestConfirmationTimeout: .milliseconds(1)
        )
        let result = await executor.execute(plan)
        #expect(result.failedCount == 1)
        #expect(result.items.first?.freedBytes == 0)
        #expect(commands.log.commands == ["xctest:\(fixture.udid)"])
    }

    @Test("Stored test-device bytes include only measured actionable devices in cleanup totals")
    func cleanupEligibilityExcludesRefusedDevices() throws {
        let idle = try Fixture()
        let booted = try Fixture()
        let unknown = try Fixture()
        defer { idle.remove()
            booted.remove()
            unknown.remove()
        }
        let devices = [idle.device(), booted.device(state: .booted), unknown.device().markingRuntimeAvailability(.unknown("lookup failed"))]
        let contents = DrillDownContent.devices(devices, sizes: [idle.udid: 100, booted.udid: 200, unknown.udid: 300])
        #expect(ScanEngine.eligibleTestDeviceBytes(contents, protectedPaths: .default) == 100)
        let protected = ProtectedPaths(customProtectedPaths: [idle.directory.appendingPathComponent("data/keep")])
        #expect(ScanEngine.eligibleTestDeviceBytes(contents, protectedPaths: protected) == 0)
        #expect(ScanEngine.eligibleTestDeviceBytes(.devices([idle.device()], sizes: [:]), protectedPaths: .default) == 0)
    }

    private struct Fixture: Sendable {
        let udid = UUID().uuidString
        var directory: URL {
            SimulatorDeviceSet.xctest().root.appendingPathComponent(udid, isDirectory: true)
        }

        var ordinaryDirectory: URL {
            SimulatorDeviceSet.ordinary().root.appendingPathComponent(udid, isDirectory: true)
        }

        let ordinaryTwin: Bool

        init(ordinaryTwin: Bool = false) throws {
            self.ordinaryTwin = ordinaryTwin
            try createOwnedDirectory(directory)
            try writePlist(state: .shutdown)
            if ordinaryTwin { try createOwnedDirectory(ordinaryDirectory) }
        }

        func writePlist(state: SimDeviceState) throws {
            let data = try PropertyListSerialization.data(
                fromPropertyList: ["UDID": udid, "name": "Cruftless disposable test", "runtime": "runtime", "state": state.rawValue],
                format: .binary,
                options: 0
            )
            try data.write(to: directory.appendingPathComponent("device.plist"), options: .atomic)
        }

        func device(state: SimDeviceState = .shutdown) -> SimDevice {
            SimDevice(udid: udid, name: "Cruftless disposable test", runtime: "runtime", state: state, lastUsedAt: nil,
                      deviceDirectory: directory, toolchainGeneration: UUID(), runtimeAvailability: .available, deviceSet: .xctest())
        }

        func createOwnedDirectory(_ url: URL) throws {
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            guard mkdir(url.path, 0o700) == 0 else { throw CocoaError(.fileWriteFileExists) }
            try Data(udid.utf8).write(to: url.appendingPathComponent(".cruftless-fixture-owner"), options: .withoutOverwriting)
        }

        func remove() {
            removeOwned(directory)
            if ordinaryTwin { removeOwned(ordinaryDirectory) }
        }

        private func removeOwned(_ url: URL) {
            guard let sentinel = try? Data(contentsOf: url.appendingPathComponent(".cruftless-fixture-owner")),
                  sentinel == Data(udid.utf8) else { return }
            TestFileSystem.removeDirectoryRecursively(at: url)
        }
    }

    private struct ScopedCommands: SimulatorCommandExecuting {
        let directory: URL
        var removesDevice = false
        let log = CommandLog()
        func shutdownSimulator(udid: String) async throws {
            log.record("shutdown:\(udid)")
        }

        func eraseSimulator(udid: String) async throws {
            log.record("erase:\(udid)")
        }

        func deleteSimulator(udid: String) async throws {
            log.record("ordinary:\(udid)")
        }

        func deleteRuntime(identifier: String) async throws {
            log.record("runtime:\(identifier)")
        }

        func deleteTestSimulator(udid: String, deviceSet: SimulatorDeviceSet) async throws {
            #expect(deviceSet.kind == .xctest)
            #expect(directory == deviceSet.root.appendingPathComponent(udid, isDirectory: true))
            log.record("xctest:\(udid)")
            if removesDevice { TestFileSystem.removeDirectoryRecursively(at: directory) }
        }
    }
}
