import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionExecutor Simulator and Identity Tests")
struct DeletionExecutorSimulatorTests {
    // MARK: - Simulator mutation ordering

    @Test("Erasing a booted simulator shuts it down first")
    func bootedEraseShutsDownFirst() async {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)

        let target = DeletionTarget.simulatorErase(
            udid: "BOOTED-1", name: "iPhone 17 Pro", isBooted: true,
            consequence: "Erase", reclaimableBytes: 4096
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(mock.log.commands == ["shutdown:BOOTED-1", "erase:BOOTED-1"])
    }

    @Test("Erasing a shut-down simulator sends no shutdown")
    func shutdownEraseSkipsShutdown() async {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)

        let target = DeletionTarget.simulatorErase(
            udid: "OFF-1", name: "iPhone 17", isBooted: false,
            consequence: "Erase", reclaimableBytes: 4096
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(mock.log.commands == ["erase:OFF-1"])
    }

    @Test("Deleting a booted simulator shuts it down first")
    func bootedDeleteShutsDownFirst() async {
        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor.testExecutor(simulatorExecutor: mock)

        let target = DeletionTarget.simulatorDelete(
            udid: "BOOTED-2", name: "iPad", isBooted: true,
            consequence: "Delete", reclaimableBytes: 8192
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(mock.log.commands == ["shutdown:BOOTED-2", "delete:BOOTED-2"])
    }

    @Test("A failed shutdown aborts the erase rather than erasing a running device")
    func failedShutdownAbortsErase() async {
        var mock = MockSimulatorExecutor()
        mock.shouldFailShutdown = true
        let executor = DeletionExecutor(simulatorExecutor: mock)

        let target = DeletionTarget.simulatorErase(
            udid: "BOOTED-3", name: "iPhone", isBooted: true,
            consequence: "Erase", reclaimableBytes: 1
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(!result.items[0].status.isSuccess)
        #expect(result.totalFreedBytes == 0)
        #expect(mock.log.commands == ["shutdown:BOOTED-3"])
    }

    // MARK: - Directory identity

    @Test("A directory whose contents changed since planning is still deleted")
    func directoryContentChangeStillDeletes() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let derived = tempBase.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: derived, withIntermediateDirectories: true)
        try "a".write(to: derived.appendingPathComponent("a.o"), atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(derived)
        let fingerprint = try #require(Fingerprint.capture(at: derived))

        try await Task.sleep(for: .milliseconds(50))
        try "b".write(to: derived.appendingPathComponent("b.o"), atomically: true, encoding: .utf8)

        let target = DeletionTarget.path(
            id: "dd", name: "DerivedData", validatedPath: validated, fingerprint: fingerprint,
            tier: .regen, consequence: "none", reclaimableBytes: 2048
        )

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
            .execute(DeletionPlan.plannedSingle(target))

        #expect(result.allSucceeded)
        #expect(!FileManager.default.fileExists(atPath: derived.path))
    }

    @Test("A directory replaced at the same path is refused")
    func replacedDirectoryRefused() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let dir = tempBase.appendingPathComponent("Cache", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(dir)
        let fingerprint = try #require(Fingerprint.capture(at: dir))

        TestFileSystem.removeDirectoryRecursively(at: dir)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try "precious".write(to: dir.appendingPathComponent("keep.txt"), atomically: true, encoding: .utf8)

        let target = DeletionTarget.path(
            id: "cache", name: "Cache", validatedPath: validated, fingerprint: fingerprint,
            tier: .regen, consequence: "none", reclaimableBytes: 1
        )

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
            .execute(DeletionPlan.plannedSingle(target))

        #expect(!result.items[0].status.isSuccess)
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("A target whose fingerprint and validated path disagree is refused")
    func mismatchedTargetRefused() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let victim = tempBase.appendingPathComponent("victim.txt")
        let decoy = tempBase.appendingPathComponent("decoy.txt")
        try "victim".write(to: victim, atomically: true, encoding: .utf8)
        try "decoy".write(to: decoy, atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(victim)
        let wrongFingerprint = try #require(Fingerprint.capture(at: decoy))

        let target = DeletionTarget.path(
            id: "mismatch", name: "mismatch", validatedPath: validated, fingerprint: wrongFingerprint,
            tier: .regen, consequence: "none", reclaimableBytes: 10
        )

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
            .execute(DeletionPlan.plannedSingle(target))

        #expect(!result.items[0].status.isSuccess)
        #expect(FileManager.default.fileExists(atPath: victim.path))
        #expect(FileManager.default.fileExists(atPath: decoy.path))
    }
}
