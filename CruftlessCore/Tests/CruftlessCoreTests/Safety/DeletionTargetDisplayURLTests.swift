import CruftlessCore
import Foundation
import Testing

@Suite("DeletionTarget display URL")
struct DeletionTargetDisplayURLTests {
    private let devicesRoot = URL(fileURLWithPath: "/Users/dev/Library/Developer/CoreSimulator/Devices", isDirectory: true)

    @Test("A simulator erase or delete shows its device folder")
    func simulatorTargetsShowDeviceFolder() {
        let erase = DeletionTarget.simulatorErase(
            udid: "UDID-1", name: "iPhone", isBooted: false, consequence: "", reclaimableBytes: 1
        )
        let delete = DeletionTarget.simulatorDelete(
            udid: "UDID-2", name: "iPad", isBooted: true, consequence: "", reclaimableBytes: 1
        )

        #expect(erase.displayURL(simulatorDevicesRoot: devicesRoot)?.path == devicesRoot.path + "/UDID-1")
        #expect(delete.displayURL(simulatorDevicesRoot: devicesRoot)?.path == devicesRoot.path + "/UDID-2")
        #expect(erase.displayURL(simulatorDevicesRoot: nil) == nil)
    }

    @Test("A path target shows its validated path")
    func pathTargetShowsValidatedPath() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        let child = root.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let validated = try PathGuard(roots: [root]).validate(child)
        let fingerprint = try #require(Fingerprint.capture(at: child))
        let target = DeletionTarget.path(
            id: "build", name: "Build", validatedPath: validated, fingerprint: fingerprint,
            tier: .regen, consequence: "", reclaimableBytes: 1
        )

        #expect(target.displayURL(simulatorDevicesRoot: devicesRoot) == validated.url)
    }

    @Test("A runtime in the root-owned store shows no path")
    func runtimeShowsNoPath() {
        let runtime = DeletionTarget.runtimeDelete(identifier: "ID", name: "iOS 27", consequence: "", reclaimableBytes: 1)

        #expect(runtime.displayURL(simulatorDevicesRoot: devicesRoot) == nil)
    }
}
