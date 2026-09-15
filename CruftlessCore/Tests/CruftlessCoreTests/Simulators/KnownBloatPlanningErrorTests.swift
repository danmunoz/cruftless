import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("KnownBloat planning refusals")
struct KnownBloatPlanningErrorTests {
    private func makeDevice(
        state: SimDeviceState,
        name: String = "iPhone Test",
        subPaths: [String] = ["tmp"],
        payload: Int = 4096
    ) throws -> (device: SimDevice, base: URL) {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let deviceDir = base.appendingPathComponent("Dev1", isDirectory: true)
        let dataDir = deviceDir.appendingPathComponent("data", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDir, withIntermediateDirectories: true)

        for relative in subPaths {
            let dir = dataDir.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            if payload > 0 {
                try Data(repeating: 0x41, count: payload).write(to: dir.appendingPathComponent("blob.bin"))
            }
        }

        let device = SimDevice(
            udid: "Dev1", name: name,
            runtime: "", state: state, lastUsedAt: nil,
            deviceDirectory: deviceDir
        )
        return (device, base)
    }

    @Test("A booted device is refused with readable copy")
    func bootedDeviceRefused() throws {
        let fixture = try makeDevice(state: .booted, name: "Booted iPhone")
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        #expect(throws: DeletionPlanningError.simulatorNotShutdown(name: "Booted iPhone")) {
            _ = try KnownBloat.createBloatDeletionPlan(for: fixture.device)
        }
    }

    @Test("A device with no data directory is refused as missing on disk")
    func missingDataDirectoryRefused() {
        let device = SimDevice(
            udid: "Dev-gone", name: "Gone iPhone",
            runtime: "", state: .shutdown, lastUsedAt: nil,
            deviceDirectory: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString, isDirectory: true)
        )

        #expect(throws: DeletionPlanningError.missingOnDisk(name: "Gone iPhone")) {
            _ = try KnownBloat.createBloatDeletionPlan(for: device)
        }
    }

    @Test("A device with none of the sub-paths is refused rather than planned empty")
    func emptyPlanRefused() throws {
        let fixture = try makeDevice(state: .shutdown, subPaths: [])
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        #expect(throws: DeletionPlanningError.nothingToPlan(title: "iPhone Test")) {
            _ = try KnownBloat.createBloatDeletionPlan(for: fixture.device)
        }
    }

    @Test("A protected sub-path refuses the plan with a readable reason")
    func protectedSubPathRefused() throws {
        let fixture = try makeDevice(state: .shutdown, subPaths: ["tmp"])
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        let tmpDir = fixture.device.dataDirectory.appendingPathComponent("tmp", isDirectory: true)
        let policy = ProtectedPaths(customProtectedPaths: [tmpDir])

        do {
            _ = try KnownBloat.createBloatDeletionPlan(for: fixture.device, protectedPaths: policy)
            Issue.record("expected a refusal")
        } catch let error as DeletionPlanningError {
            #expect(error == .refused(name: "iPhone Test · Temporary files", error: .protectedPath(ProtectedPaths.normalize(tmpDir))))
            #expect(!(error.errorDescription ?? "").isEmpty)
        }
    }

    @Test("Every sub-path present on disk reaches the plan")
    func planCoversEverySubPath() throws {
        let fixture = try makeDevice(
            state: .shutdown,
            subPaths: ["tmp", "Library/Caches", "Library/Application Support/PRBPosterExtensionDataStore"]
        )
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        let plan = try KnownBloat.createBloatDeletionPlan(for: fixture.device)

        #expect(plan.count == 3)
        #expect(plan.totalReclaimableBytes > 0)
        #expect(plan.items.allSatisfy { $0.reclaimableBytes > 0 })
        #expect(plan.confirmLabel == "Clear \(ByteFormatter.format(plan.totalReclaimableBytes))")
    }
}
