import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionExecutor Tests")
struct DeletionExecutorTests {
    @Test("Empty plan returns empty result with 0 freed bytes")
    func emptyPlanExecution() async {
        let executor = DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
        let result = await executor.execute(DeletionPlan.batch([]))
        #expect(result.items.isEmpty)
        #expect(result.totalFreedBytes == 0)
        #expect(!result.hasFailures)
    }

    @Test("Re-stat case 1: Valid unmodified file is deleted and bytes recorded")
    func validFileDeletion() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let targetFile = tempBase.appendingPathComponent("build.artifact")
        try "artifact data".write(to: targetFile, atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(targetFile)
        let fingerprint = try #require(Fingerprint.capture(at: targetFile))

        let target = DeletionTarget.path(
            id: "artifact",
            name: "artifact",
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: .regen,
            consequence: "Xcode recreates on build",
            reclaimableBytes: 1024
        )

        let executor = DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
        let plan = DeletionPlan.single(target)
        let result = await executor.execute(plan)

        #expect(result.allSucceeded)
        #expect(result.totalFreedBytes == 1024)
        #expect(!FileManager.default.fileExists(atPath: targetFile.path))
    }

    @Test("Re-stat case 2: File missing before delete reports failure without crashing")
    func missingFileReStat() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let targetFile = tempBase.appendingPathComponent("vanishing.artifact")
        try "temp".write(to: targetFile, atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(targetFile)
        let fingerprint = try #require(Fingerprint.capture(at: targetFile))

        TestFileSystem.removeFile(at: targetFile)

        let target = DeletionTarget.path(
            id: "missing",
            name: "missing",
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: .regen,
            consequence: "none",
            reclaimableBytes: 500
        )

        let executor = DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.items.count == 1)
        #expect(!result.items[0].status.isSuccess)
        #expect(result.totalFreedBytes == 0)
    }

    @Test("Re-stat case 3: File modified after scan is refused as changed-since-scan")
    func fileModifiedAfterScanRefused() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let targetFile = tempBase.appendingPathComponent("mutating.artifact")
        try "initial".write(to: targetFile, atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(targetFile)
        let initialFingerprint = try #require(Fingerprint.capture(at: targetFile))

        try await Task.sleep(for: .milliseconds(50))
        try "modified contents".write(to: targetFile, atomically: true, encoding: .utf8)

        let target = DeletionTarget.path(
            id: "mutated",
            name: "mutated",
            validatedPath: validated,
            fingerprint: initialFingerprint,
            tier: .regen,
            consequence: "none",
            reclaimableBytes: 500
        )

        let executor = DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.items.count == 1)
        #expect(!result.items[0].status.isSuccess)
        #expect(result.items[0].status.failureReason?.contains("changed since scan") == true)
        #expect(result.totalFreedBytes == 0)
        #expect(FileManager.default.fileExists(atPath: targetFile.path))
    }

    @Test("Re-stat case 4: File replaced with different inode is refused")
    func fileReplacedInodeRefused() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let targetFile = tempBase.appendingPathComponent("replaced.artifact")
        try "initial".write(to: targetFile, atomically: true, encoding: .utf8)

        let guardInstance = PathGuard(roots: [tempBase])
        let validated = try guardInstance.validate(targetFile)
        let initialFingerprint = try #require(Fingerprint.capture(at: targetFile))

        TestFileSystem.removeFile(at: targetFile)
        try "replacement".write(to: targetFile, atomically: true, encoding: .utf8)

        let target = DeletionTarget.path(
            id: "replaced",
            name: "replaced",
            validatedPath: validated,
            fingerprint: initialFingerprint,
            tier: .regen,
            consequence: "none",
            reclaimableBytes: 500
        )

        let executor = DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.items.count == 1)
        #expect(!result.items[0].status.isSuccess)
        #expect(result.totalFreedBytes == 0)
    }

    @Test("Batch execution never aborts early and collects all outcomes (3-item batch with middle failure)")
    func batchDeletesNeverAbortEarly() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let guardInstance = PathGuard(roots: [tempBase])

        let file1 = tempBase.appendingPathComponent("item1.txt")
        try "1".write(to: file1, atomically: true, encoding: .utf8)
        let val1 = try guardInstance.validate(file1)
        let fp1 = try #require(Fingerprint.capture(at: file1))
        let target1 = DeletionTarget.path(
            id: "1", name: "1", validatedPath: val1, fingerprint: fp1,
            tier: .regen, consequence: "none", reclaimableBytes: 100
        )

        let file2 = tempBase.appendingPathComponent("item2.txt")
        try "2".write(to: file2, atomically: true, encoding: .utf8)
        let val2 = try guardInstance.validate(file2)
        let fp2 = try #require(Fingerprint.capture(at: file2))
        TestFileSystem.removeFile(at: file2)
        let target2 = DeletionTarget.path(
            id: "2", name: "2", validatedPath: val2, fingerprint: fp2,
            tier: .regen, consequence: "none", reclaimableBytes: 200
        )

        let file3 = tempBase.appendingPathComponent("item3.txt")
        try "3".write(to: file3, atomically: true, encoding: .utf8)
        let val3 = try guardInstance.validate(file3)
        let fp3 = try #require(Fingerprint.capture(at: file3))
        let target3 = DeletionTarget.path(
            id: "3", name: "3", validatedPath: val3, fingerprint: fp3,
            tier: .regen, consequence: "none", reclaimableBytes: 300
        )

        let executor = DeletionExecutor(simulatorExecutor: MockSimulatorExecutor())
        let plan = DeletionPlan.batch([target1, target2, target3])
        let result = await executor.execute(plan)

        #expect(result.items.count == 3)
        #expect(result.items[0].status.isSuccess)
        #expect(!result.items[1].status.isSuccess)
        #expect(result.items[2].status.isSuccess)
        #expect(result.totalFreedBytes == 400) // 100 + 300
        #expect(result.succeededCount == 2)
        #expect(result.failedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: file1.path))
        #expect(!FileManager.default.fileExists(atPath: file3.path))
    }

    @Test("Batch plan strictly excludes flagged (⚠) entries")
    func batchExcludesFlaggedItems() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let guardInstance = PathGuard(roots: [tempBase])
        let file1 = tempBase.appendingPathComponent("archive.xcarchive")
        try "dsym".write(to: file1, atomically: true, encoding: .utf8)
        let val1 = try guardInstance.validate(file1)
        let fp1 = try #require(Fingerprint.capture(at: file1))

        let flaggedTarget = DeletionTarget.path(
            id: "archive", name: "archive", validatedPath: val1, fingerprint: fp1,
            tier: .irreversible, consequence: "Loss of dSYMs", reclaimableBytes: 5000
        )

        let normalTarget = DeletionTarget.simulatorErase(
            udid: "UUID-1", name: "iPhone 16", isBooted: false,
            consequence: "Erase data", reclaimableBytes: 1000
        )

        let batch = DeletionPlan.batch([flaggedTarget, normalTarget])
        #expect(batch.items.count == 1)
        #expect(batch.items[0].id == normalTarget.id)
        #expect(batch.totalReclaimableBytes == 1000)
    }

    @Test("A lone flagged target survives only through .single, never .batch")
    func flaggedTargetOnlyPlannableThroughSingle() throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let guardInstance = PathGuard(roots: [tempBase])
        let file = tempBase.appendingPathComponent("archive.xcarchive")
        try "dsym".write(to: file, atomically: true, encoding: .utf8)
        let validated = try guardInstance.validate(file)
        let fingerprint = try #require(Fingerprint.capture(at: file))

        let flaggedTarget = DeletionTarget.path(
            id: "archive", name: "archive", validatedPath: validated, fingerprint: fingerprint,
            tier: .irreversible, consequence: "Loss of dSYMs", reclaimableBytes: 2000
        )

        let batched = DeletionPlan.batch([flaggedTarget])
        #expect(batched.isEmpty)
        #expect(!batched.hasFlaggedItem)

        let single = DeletionPlan.single(flaggedTarget)
        #expect(single.items.count == 1)
        #expect(single.hasFlaggedItem)
    }
}

private actor Latch {
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        guard !isOpen else { return }
        isOpen = true
        let pending = waiters
        waiters = []
        for continuation in pending {
            continuation.resume()
        }
    }

    func wait() async {
        if isOpen { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private final class GatedSimulatorExecutor: SimulatorCommandExecuting {
    let entered = Latch()
    let release = Latch()
    private let counter = EraseCounter()

    var eraseCount: Int {
        counter.value
    }

    func shutdownSimulator(udid _: String) async throws {}

    func eraseSimulator(udid _: String) async throws {
        counter.increment()
        await entered.open()
        await release.wait()
    }

    func deleteSimulator(udid _: String) async throws {}
    func deleteRuntime(identifier _: String) async throws {}
}

private final class EraseCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        count += 1
    }

    var value: Int {
        lock.lock()
        defer { lock.unlock() }
        return count
    }
}

@Suite("DeletionExecutor reentrancy")
struct DeletionExecutorReentrancyTests {
    private static func erase(udid: String) -> DeletionTarget {
        .simulatorErase(
            udid: udid,
            name: "Sim \(udid)",
            isBooted: false,
            consequence: "Erases the device",
            reclaimableBytes: 4096
        )
    }

    @Test("A second execute arriving mid-run is refused, not interleaved", .timeLimit(.minutes(1)))
    func overlappingExecuteIsRefused() async {
        let mock = GatedSimulatorExecutor()
        let executor = DeletionExecutor(simulatorExecutor: mock)

        let first = Task {
            await executor.execute(DeletionPlan.single(Self.erase(udid: "FIRST")))
        }
        await mock.entered.wait()

        let second = await executor.execute(DeletionPlan.single(Self.erase(udid: "SECOND")))

        #expect(second.items.count == 1)
        #expect(!second.hasFailures)
        #expect(second.notAttemptedCount == 1)
        #expect(second.totalFreedBytes == 0)
        #expect(second.items[0].status.isNotAttempted)
        #expect(second.items[0].status.notAttemptedReason == NotAttemptedReason.executorBusy.copy)
        #expect(mock.eraseCount == 1)

        await mock.release.open()
        let firstResult = await first.value
        #expect(firstResult.allSucceeded)
        #expect(firstResult.totalFreedBytes == 4096)
    }

    @Test("The guard clears once the run finishes", .timeLimit(.minutes(1)))
    func guardClearsAfterRun() async {
        let mock = GatedSimulatorExecutor()
        await mock.release.open()
        let executor = DeletionExecutor(simulatorExecutor: mock)

        let first = await executor.execute(DeletionPlan.single(Self.erase(udid: "ONE")))
        let second = await executor.execute(DeletionPlan.single(Self.erase(udid: "TWO")))

        #expect(first.allSucceeded)
        #expect(second.allSucceeded)
        #expect(mock.eraseCount == 2)
    }
}
