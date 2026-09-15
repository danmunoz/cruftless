import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("KnownBloat Zero-Size and Erase Confirm Label Tests")
struct KnownBloatZeroSizeAndEraseLabelTests {
    @Test("KnownBloat.scanBloat skips a sub-path with zero allocated bytes")
    func scanBloatSkipsEmptySubPath() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let deviceDir = tempBase.appendingPathComponent("Dev1")
        let dataDir = deviceDir.appendingPathComponent("data")
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let tmpDir = dataDir.appendingPathComponent("tmp")
        try FileManager.default.createDirectory(at: tmpDir, withIntermediateDirectories: true)

        let simDevice = SimDevice(
            udid: "Dev1", name: "iPhone Test",
            runtime: "", state: .shutdown, lastUsedAt: nil,
            deviceDirectory: deviceDir
        )

        let results = KnownBloat.scanBloat(for: simDevice, inodeSet: InodeSet())
        #expect(results.isEmpty)
    }

    @Test("Erase plan confirm label matches the device's boot state")
    func eraseConfirmLabelMatchesBootState() throws {
        let bootedDevice = SimDevice(
            udid: "00000000-0000-4000-8000-0000000000B0", name: "Booted iPhone",
            runtime: "", state: .booted, lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/cruftless-erase-booted")
        )
        let bootedPlan = try DeletionPlanner.simulatorErase(for: bootedDevice, context: PlanningContext())
        #expect(bootedPlan.confirmLabel == "Shut Down and Erase")

        let shutdownDevice = SimDevice(
            udid: "00000000-0000-4000-8000-0000000000F0", name: "Shut Down iPhone",
            runtime: "", state: .shutdown, lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/cruftless-erase-off")
        )
        let shutdownPlan = try DeletionPlanner.simulatorErase(for: shutdownDevice, context: PlanningContext())
        #expect(shutdownPlan.confirmLabel == "Delete Permanently")
    }
}
