import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("Simulator Subsystem Tests")
struct SimulatorsTests {
    @Test("ImagesPlist parses verified schema and handles malformed plists")
    func imagesPlistParsing() {
        let validPlist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>images</key>
            <array>
                <dict>
                    <key>runtimeInfo</key>
                    <dict>
                        <key>build</key>
                        <string>22G86</string>
                        <key>bundleIdentifier</key>
                        <string>com.apple.CoreSimulator.SimRuntime.iOS-18-6</string>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """.utf8)

        let runtimes = ImagesPlist.parse(data: validPlist)
        #expect(runtimes != nil)
        #expect(runtimes?.count == 1)
        #expect(runtimes?.first?.build == "22G86")
        #expect(runtimes?.first?.runtimeIdentifier == "com.apple.CoreSimulator.SimRuntime.iOS-18-6")

        let malformed = Data("not a plist".utf8)
        #expect(ImagesPlist.parse(data: malformed) == nil)
    }

    @Test("DeviceStore parses 21-device tree, maps states, and skips isDeleted")
    func deviceStoreTree() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        for index in 1 ... 21 {
            let udid = "00000000-0000-4000-8000-\(String(format: "%012d", index))"
            let deviceDir = tempBase.appendingPathComponent(udid, isDirectory: true)
            try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)

            let isDeleted = (index == 21)
            let state = (index <= 5) ? 3 : 1 // 1-5 booted, 6-20 shutdown
            let plistDict: [String: Any] = [
                "UDID": udid,
                "name": "iPhone \(index)",
                "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-16",
                "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
                "state": state,
                "isDeleted": isDeleted,
                "lastUsedAt": Date()
            ]
            let plistData = try PropertyListSerialization.data(fromPropertyList: plistDict, format: .xml, options: 0)
            try plistData.write(to: deviceDir.appendingPathComponent("device.plist"))
        }

        let loaded = DeviceStore.loadDevices(from: tempBase)
        #expect(loaded.count == 20)

        let booted = loaded.filter(\.state.isBooted)
        let shutdown = loaded.filter(\.state.isShutdown)
        #expect(booted.count == 5)
        #expect(shutdown.count == 15)
    }

    @Test("UnavailableDetector flags devices with missing runtimes and sorts them first")
    func unavailableDeviceDetection() {
        let installedRuntime = SimRuntime(
            identifier: "UUID-R1",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
            name: "iOS 18.6",
            build: "22G86",
            sizeBytes: 1000,
            isDeletable: true
        )

        let devNormal = SimDevice(
            udid: "U1", name: "Alpha Phone",
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
            state: .shutdown, lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/dev/u1")
        )

        let devOrphan = SimDevice(
            udid: "U2", name: "Beta Phone",
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-17-0", // Removed runtime
            state: .shutdown, lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/dev/u2")
        )

        let reconciled = UnavailableDetector.reconcile(devices: [devNormal, devOrphan], runtimes: [installedRuntime])
        let sorted = UnavailableDetector.sort(devices: reconciled)

        #expect(sorted.first?.udid == "U2")
        #expect(sorted.first?.isUnavailable == true)
        #expect(sorted.last?.udid == "U1")
        #expect(sorted.last?.isUnavailable == false)
    }

    @Test("KnownBloat guard admits the 3 subpaths and strictly rejects ../device.plist, device root, and sibling device")
    func knownBloatGuardSecurity() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let deviceDir = tempBase.appendingPathComponent("Dev1")
        let dataDir = deviceDir.appendingPathComponent("data")
        let siblingDeviceDir = tempBase.appendingPathComponent("Dev2")
        let siblingDataDir = siblingDeviceDir.appendingPathComponent("data")

        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: siblingDataDir, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let posterDir = dataDir.appendingPathComponent("Library/Application Support/PRBPosterExtensionDataStore")
        let cachesDir = dataDir.appendingPathComponent("Library/Caches")
        let tmpDir = dataDir.appendingPathComponent("tmp")

        try FileManager.default.createDirectory(at: posterDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: cachesDir, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let devicePlist = deviceDir.appendingPathComponent("device.plist")
        try "plist".write(to: devicePlist, atomically: true, encoding: .utf8)

        let simDevice = SimDevice(
            udid: "Dev1", name: "iPhone Test",
            runtime: "", state: .shutdown, lastUsedAt: nil,
            deviceDirectory: deviceDir
        )

        let plan = try KnownBloat.createBloatDeletionPlan(for: simDevice)
        #expect(plan.items.count == 3)
        #expect(plan.affectedLocationIds == Set([LocationCatalog.simulatorDevices.id]))

        let customProtection = ProtectedPaths(customProtectedPaths: [cachesDir])
        let refusal = DeletionPlanningError.refused(
            name: "iPhone Test · Caches",
            error: .protectedPath(ProtectedPaths.normalize(cachesDir))
        )
        #expect(throws: refusal) {
            _ = try KnownBloat.createBloatDeletionPlan(for: simDevice, protectedPaths: customProtection)
        }

        let guardInstance = PathGuard(roots: [dataDir])

        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(devicePlist)
        }

        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(deviceDir)
        }

        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(siblingDataDir)
        }

        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(dataDir)
        }
    }

    @Test("KnownBloat refuses deletion if device is booted")
    func knownBloatRefusesBootedDevice() {
        let bootedDevice = SimDevice(
            udid: "00000000-0000-4000-8000-0000000000B0", name: "Booted iPhone",
            runtime: "", state: .booted, lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/booted")
        )

        #expect(throws: DeletionPlanningError.simulatorNotShutdown(name: "Booted iPhone")) {
            _ = try KnownBloat.createBloatDeletionPlan(for: bootedDevice)
        }
    }

    @Test("Simulator erase planning refuses a custom protected descendant")
    func simulatorEraseRefusesProtectedDescendant() {
        let deviceRoot = URL(fileURLWithPath: "/tmp/cruftless-simulator-protected")
        let device = SimDevice(
            udid: "00000000-0000-4000-8000-0000000000C0", name: "Protected iPhone",
            runtime: "", state: .shutdown, lastUsedAt: nil,
            deviceDirectory: deviceRoot
        )
        let protectedPath = deviceRoot.appendingPathComponent("data/Documents")

        #expect(throws: DeletionPlanningError.protectedDescendantInSimulator(
            name: "Protected iPhone",
            path: deviceRoot.path
        )) {
            _ = try DeletionPlanner.simulatorErase(
                for: device,
                context: PlanningContext(protectedPaths: ProtectedPaths(customProtectedPaths: [protectedPath]))
            )
        }
    }

    @Test("An erase plan rescans the devices location")
    func erasePlanScopesRescan() throws {
        let device = SimDevice(
            udid: "00000000-0000-4000-8000-0000000000E0", name: "Erase iPhone",
            runtime: "", state: .shutdown, lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/cruftless-erase-scope")
        )
        let plan = try DeletionPlanner.simulatorErase(for: device, context: PlanningContext())
        #expect(plan.affectedLocationIds == Set([LocationCatalog.simulatorDevices.id]))
    }

    @Test("SimctlRunner returns typed errors on failure and malformed JSON")
    func simctlRunnerErrors() async {
        let failExecutor = SimctlDouble(status: 1, stderr: "simctl error occurred")
        let runnerFail = SimctlRunner(executor: failExecutor)
        await #expect(throws: SimctlError.self) {
            _ = try await runnerFail.listRuntimes()
        }

        let badJsonExecutor = SimctlDouble(stdout: "<html>not json</html>")
        let runnerBadJson = SimctlRunner(executor: badJsonExecutor)
        await #expect(throws: SimctlError.self) {
            _ = try await runnerBadJson.listRuntimes()
        }
    }

    // MARK: - Fail-closed planning

    @Test("Planning a bundled runtime deletion fails closed")
    func bundledRuntimePlanRefused() {
        let bundled = SimRuntime(
            identifier: "R1",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            name: "iOS 27.0",
            build: "24A5418b",
            sizeBytes: 8_000_000_000,
            isDeletable: false
        )
        #expect(throws: DeletionPlanningError.runtimeNotDeletable(name: "iOS 27.0")) {
            try DeletionPlanner.runtimeDelete(bundled, context: PlanningContext())
        }
    }

    @Test("Planning a downloadable runtime deletion succeeds")
    func downloadableRuntimePlanned() throws {
        let downloadable = SimRuntime(
            identifier: "R2",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-0",
            name: "iOS 26.0",
            build: "23A123",
            sizeBytes: 7_000_000_000,
            isDeletable: true
        )
        let plan = try DeletionPlanner.runtimeDelete(downloadable, context: PlanningContext())
        #expect(plan.count == 1)
        #expect(plan.totalReclaimableBytes == 7_000_000_000)
        #expect(plan.items[0].consequence.contains("must be re-downloaded to run simulators on this OS version."))
        #expect(plan.items[0].consequence.contains("Simulators that use it stop working until it is installed again."))
        #expect(plan.affectedLocationIds == Set([LocationCatalog.simulatorRuntimes.id, LocationCatalog.simulatorDevices.id]))
    }

    @Test("Shutdown tolerates a device that is already shut down")
    func shutdownToleratesAlreadyOff() async throws {
        let executor = SimctlDouble(
            status: 164,
            stderr: "Unable to shutdown device in current state: Shutdown"
        )
        try await SimctlRunner(executor: executor).shutdown(udid: "00000000-0000-4000-8000-000000000001")
    }

    @Test("Shutdown still reports a genuine failure")
    func shutdownReportsRealFailure() async {
        let executor = SimctlDouble(
            status: 1,
            stderr: "Invalid device: NOPE"
        )
        await #expect(throws: SimctlError.self) {
            try await SimctlRunner(executor: executor).shutdown(udid: "00000000-0000-4000-8000-00000000BAD0")
        }
    }

    @Test("Executor handles output larger than the pipe buffer without hanging")
    func largeOutputDoesNotDeadlock() async throws {
        let output = try await BoundedProcess.run(
            executable: URL(fileURLWithPath: "/bin/dd"),
            arguments: ["if=/dev/zero", "bs=65536", "count=4"],
            environment: [:],
            timeout: .seconds(10)
        )
        #expect(output.status == 0)
        #expect(output.stdoutData.count == 65536 * 4)
    }
}
