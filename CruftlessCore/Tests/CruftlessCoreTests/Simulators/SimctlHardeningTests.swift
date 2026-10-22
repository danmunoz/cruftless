import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("simctl hardening")
struct SimctlHardeningTests {
    private let validUDID = "6E3C5A2B-1F0D-4E8A-9B7C-0123456789AB"

    @Test("A device identifier that is not a UUID never reaches simctl")
    func nonUUIDDeviceRefused() async {
        let executor = SimctlDouble()
        let runner = SimctlRunner(executor: executor)

        for bad in ["all", "booted", "", "-h", "NOPE", "6E3C5A2B-1F0D-4E8A-9B7C"] {
            await #expect(throws: SimctlError.invalidIdentifier(bad), "\(bad)") {
                try await runner.erase(udid: bad)
            }
            await #expect(throws: SimctlError.invalidIdentifier(bad), "\(bad)") {
                try await runner.delete(udid: bad)
            }
            await #expect(throws: SimctlError.invalidIdentifier(bad), "\(bad)") {
                try await runner.shutdown(udid: bad)
            }
        }
        #expect(executor.arguments.isEmpty)
    }

    @Test("A valid UDID is passed through in canonical uppercase form")
    func validUDIDPassesThrough() async throws {
        let executor = SimctlDouble()
        try await SimctlRunner(executor: executor).erase(udid: validUDID.lowercased())
        #expect(executor.arguments == [["erase", validUDID]])
    }

    @Test("XCTest deletion is scoped to the validated test device set")
    func xctestDeleteUsesSetArgument() async throws {
        let executor = SimctlDouble()
        let set = SimulatorDeviceSet.xctest()
        try await SimctlRunner(executor: executor).delete(udid: validUDID, in: set)
        #expect(executor.arguments == [["--set", set.root.path(percentEncoded: false), "delete", validUDID]])
    }

    @Test("Runtime sentinels and flags are refused; real identifiers pass")
    func runtimeIdentifierValidation() async throws {
        let executor = SimctlDouble()
        let runner = SimctlRunner(executor: executor)

        for bad in ["all", "ALL", "", "-j", "--all", "com.apple x", "id;rm", ".", "..", "...", ".hidden"] {
            await #expect(throws: SimctlError.invalidIdentifier(bad), "\(bad)") {
                try await runner.runtimeDelete(identifier: bad)
            }
        }
        #expect(executor.arguments.isEmpty)

        try await runner.runtimeDelete(identifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0")
        try await runner.runtimeDelete(identifier: validUDID)
        #expect(executor.arguments == [
            ["runtime", "delete", "com.apple.CoreSimulator.SimRuntime.iOS-26-0"],
            ["runtime", "delete", validUDID]
        ])
    }

    @Test("A device.plist with a non-UUID UDID is not loaded")
    func deviceStoreDropsBadUDID() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let plist = base.appendingPathComponent("device.plist")
        let dict: [String: Any] = ["UDID": "all", "name": "Evil", "state": 1]
        try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0).write(to: plist)

        #expect(DeviceStore.parseDevicePlist(at: plist, deviceDirectory: base) == nil)
    }

    @Test("Device-store identity includes its set and rejects folder-plist mismatches")
    func deviceStoreScopesIdentityAndChecksFolderName() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let udidDirectory = base.appendingPathComponent(validUDID, isDirectory: true)
        try FileManager.default.createDirectory(at: udidDirectory, withIntermediateDirectories: false)
        try writeDevicePlist(udid: validUDID, to: udidDirectory.appendingPathComponent("device.plist"))
        let set = SimulatorDeviceSet(kind: .xctest, root: base)

        let loaded = DeviceStore.loadDevices(in: set)
        #expect(loaded.count == 1)
        #expect(loaded[0].deviceSet.id == "xctest")
        #expect(loaded[0].id != SimDevice(
            udid: validUDID,
            name: "Clone",
            runtime: "",
            state: .shutdown,
            lastUsedAt: nil,
            deviceDirectory: udidDirectory
        ).id)

        let mismatchedDirectory = base.appendingPathComponent("A1B2C3D4-1111-2222-3333-ABCDEF012345", isDirectory: true)
        try FileManager.default.createDirectory(at: mismatchedDirectory, withIntermediateDirectories: false)
        try writeDevicePlist(udid: validUDID, to: mismatchedDirectory.appendingPathComponent("device.plist"))
        #expect(DeviceStore.loadDevices(in: set).count == 1)
    }

    @Test("Device store refuses linked roots, device folders, and metadata")
    func deviceStoreRejectsSymlinks() throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let realRoot = base.appendingPathComponent("real", isDirectory: true)
        let linkedRoot = base.appendingPathComponent("linked", isDirectory: true)
        try FileManager.default.createDirectory(at: realRoot, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: realRoot)
        let linkedSet = SimulatorDeviceSet(kind: .xctest, root: linkedRoot)
        #expect(DeviceStore.loadDevices(in: linkedSet).isEmpty)

        let linkedDevice = realRoot.appendingPathComponent("A1B2C3D4-1111-2222-3333-ABCDEF012345", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedDevice, withDestinationURL: base)
        #expect(DeviceStore.loadDevices(in: SimulatorDeviceSet(kind: .xctest, root: realRoot)).isEmpty)

        let regularDevice = realRoot.appendingPathComponent(validUDID, isDirectory: true)
        try FileManager.default.createDirectory(at: regularDevice, withIntermediateDirectories: false)
        let backingPlist = base.appendingPathComponent("backing.plist")
        try writeDevicePlist(udid: validUDID, to: backingPlist)
        try FileManager.default.createSymbolicLink(
            at: regularDevice.appendingPathComponent("device.plist"),
            withDestinationURL: backingPlist
        )
        #expect(DeviceStore.loadDevices(in: SimulatorDeviceSet(kind: .xctest, root: realRoot)).isEmpty)
    }

    private func writeDevicePlist(udid: String, to url: URL) throws {
        let dict: [String: Any] = ["UDID": udid, "name": "Clone", "state": 1]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
    }

    @Test("Planning a simulator action validates the UDID before review")
    func planningValidatesUDID() throws {
        let device = SimDevice(
            udid: "booted", name: "Evil", runtime: "", state: .shutdown,
            lastUsedAt: nil, deviceDirectory: URL(fileURLWithPath: "/tmp/never")
        )
        #expect(throws: SimctlError.invalidIdentifier("booted")) {
            try DeletionPlanner.simulatorErase(for: device, context: PlanningContext())
        }
        #expect(throws: SimctlError.invalidIdentifier("booted")) {
            try DeletionPlanner.simulatorDelete(for: device, context: PlanningContext())
        }
    }

    @Test("Child environment drops DEVELOPER_DIR and DYLD_* and pins PATH")
    func childEnvironmentIsMinimal() {
        let inherited = [
            "HOME": "/Users/x",
            "USER": "x",
            "PATH": "/evil/bin:/usr/bin",
            "DEVELOPER_DIR": "/Volumes/Evil/Xcode.app/Contents/Developer",
            "DYLD_INSERT_LIBRARIES": "/evil.dylib",
            "TMPDIR": "/tmp/x"
        ]
        let environment = DefaultSimctlExecutor.childEnvironment(from: inherited)
        #expect(environment["HOME"] == "/Users/x")
        #expect(environment["USER"] == "x")
        #expect(environment["TMPDIR"] == "/tmp/x")
        #expect(environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["DEVELOPER_DIR"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
    }

    @Test("A wedged child is terminated and reported as timed out", .timeLimit(.minutes(1)))
    func timeoutTerminatesWedgedChild() async throws {
        let capturedPID = PIDBox()
        let executor = DefaultSimctlExecutor(
            timeout: .milliseconds(300),
            executableURL: URL(fileURLWithPath: "/bin/sleep"),
            argumentPrefix: [],
            onLaunch: { pid in capturedPID.set(pid) }
        )
        let clock = ContinuousClock()
        let start = clock.now
        await #expect(throws: SimctlError.timedOut("30")) {
            _ = try await executor.run(arguments: ["30"])
        }
        #expect(clock.now - start < .seconds(10))

        let pid = try #require(capturedPID.value)
        var stillRunning = true
        for _ in 0 ..< 50 {
            if kill(pid, 0) == -1, errno == ESRCH {
                stillRunning = false
                break
            }
            try await Task.sleep(for: .milliseconds(100))
        }
        #expect(!stillRunning, "child pid \(pid) should have been killed")
    }

    @Test("A child that exits promptly is not affected by the timeout")
    func fastChildCompletes() async throws {
        let executor = DefaultSimctlExecutor(
            timeout: .seconds(10),
            executableURL: URL(fileURLWithPath: "/bin/echo"),
            argumentPrefix: []
        )
        let output = try await executor.run(arguments: ["hello"])
        #expect(output.status == 0)
        #expect(output.stdout.trimmingCharacters(in: .whitespacesAndNewlines) == "hello")
    }

    @Test("A child that outfills the stderr pipe buffer does not deadlock")
    func largeStderrOutputDoesNotDeadlock() async throws {
        let executor = DefaultSimctlExecutor(
            timeout: .seconds(10),
            executableURL: URL(fileURLWithPath: "/bin/sh"),
            argumentPrefix: []
        )
        let output = try await executor.run(arguments: [
            "-c",
            "yes 1234567890 | head -c 262144 1>&2"
        ])
        #expect(output.status == 0)
        #expect(output.stderr.utf8.count == 262_144)
    }

    // MARK: - Pure timeout decision (BoundedProcess.shouldReportTimeout)

    @Test("A clean exit is never reported as a timeout, even if the flag was set")
    func timeoutDecisionIgnoresCleanExit() {
        #expect(BoundedProcess.shouldReportTimeout(timedOut: true, terminationReason: .exit) == false)
        #expect(BoundedProcess.shouldReportTimeout(timedOut: false, terminationReason: .exit) == false)
    }

    @Test("An uncaught signal is only reported as a timeout when the killer fired")
    func timeoutDecisionRequiresBothSignals() {
        #expect(BoundedProcess.shouldReportTimeout(timedOut: true, terminationReason: .uncaughtSignal) == true)
        #expect(BoundedProcess.shouldReportTimeout(timedOut: false, terminationReason: .uncaughtSignal) == false)
    }
}

private final class PIDBox: @unchecked Sendable {
    private let lock = NSLock()
    private var pid: pid_t?

    func set(_ value: pid_t) {
        lock.lock()
        defer { lock.unlock() }
        pid = value
    }

    var value: pid_t? {
        lock.lock()
        defer { lock.unlock() }
        return pid
    }
}
