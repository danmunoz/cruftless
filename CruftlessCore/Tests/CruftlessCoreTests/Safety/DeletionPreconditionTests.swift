import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("Deletion precondition re-check")
struct DeletionPreconditionTests {
    private struct Fixture {
        let base: URL
        let device: URL
        let plist: URL
        let cache: URL
    }

    private func makeDevice(state: Int) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let device = base.appendingPathComponent("CoreSimulator/Devices/\(UUID().uuidString)", isDirectory: true)
        let data = device.appendingPathComponent("data", isDirectory: true)
        let cache = data.appendingPathComponent("Library/Caches", isDirectory: true)
        try FileManager.default.createDirectory(at: cache, withIntermediateDirectories: true)
        try "blob".write(to: cache.appendingPathComponent("blob"), atomically: true, encoding: .utf8)

        let plist = device.appendingPathComponent("device.plist")
        try writePlist(state: state, to: plist, udid: device.lastPathComponent)
        return Fixture(base: base, device: device, plist: plist, cache: cache)
    }

    private func writePlist(state: Int, to url: URL, udid: String) throws {
        let dict: [String: Any] = ["UDID": udid, "name": "iPhone Test", "state": state]
        let data = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        try data.write(to: url)
    }

    private func target(for fixture: Fixture) throws -> DeletionTarget {
        let pathGuard = PathGuard(roots: [fixture.device.appendingPathComponent("data", isDirectory: true)])
        let validated = try pathGuard.validate(fixture.cache)
        let fingerprint = try #require(Fingerprint.capture(at: fixture.cache))
        return .path(
            id: "bloat",
            name: "Caches",
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: .regen,
            consequence: "regen",
            reclaimableBytes: 4,
            precondition: .simulatorShutdown(devicePlist: fixture.plist, deviceName: "iPhone Test")
        )
    }

    @Test("A device booted after planning refuses the known-bloat delete")
    func bootedAfterPlanningRefuses() async throws {
        let fixture = try makeDevice(state: 1)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let plan = try DeletionPlan.plannedSingle(target(for: fixture))

        try writePlist(state: 3, to: fixture.plist, udid: fixture.device.lastPathComponent)

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        #expect(result.failedCount == 1)
        #expect(result.items[0].status.failureReason?.contains("no longer shut down") == true)
        #expect(FileManager.default.fileExists(atPath: fixture.cache.path))
    }

    @Test("A device still shut down at execute time is cleared")
    func stillShutdownProceeds() async throws {
        let fixture = try makeDevice(state: 1)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let plan = try DeletionPlan.plannedSingle(target(for: fixture))

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        #expect(result.allSucceeded)
        #expect(!FileManager.default.fileExists(atPath: fixture.cache.path))
        #expect(FileManager.default.fileExists(atPath: fixture.plist.path))
    }

    @Test("An unreadable device.plist fails closed")
    func unreadablePlistRefuses() async throws {
        let fixture = try makeDevice(state: 1)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let plan = try DeletionPlan.plannedSingle(target(for: fixture))

        TestFileSystem.removeFile(at: fixture.plist)

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        #expect(result.failedCount == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.cache.path))
    }

    @Test("KnownBloat attaches the shutdown precondition to every target")
    func knownBloatPlanCarriesPrecondition() throws {
        let fixture = try makeDevice(state: 1)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let device = try #require(DeviceStore.parseDevicePlist(at: fixture.plist, deviceDirectory: fixture.device))

        let plan = try KnownBloat.createBloatDeletionPlan(for: device)
        #expect(!plan.isEmpty)
        for item in plan.items {
            #expect(item.precondition == .simulatorShutdown(devicePlist: fixture.plist, deviceName: "iPhone Test"))
        }
    }
}
