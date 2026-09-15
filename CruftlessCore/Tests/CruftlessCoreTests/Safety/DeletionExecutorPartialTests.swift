import CruftlessCore
import CruftlessFixtures
import Darwin
import Foundation
import Testing

@Suite("DeletionExecutor partial removal and cancellation")
struct DeletionExecutorPartialTests {
    private struct Fixture {
        let base: URL
        let target: URL
        let plannedBytes: Int64
    }

    private func makeTarget(under parent: String, fileCount: Int = 6) throws -> Fixture {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let outer = base.appendingPathComponent(parent, isDirectory: true)
        let target = outer.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)
        for index in 0 ..< fileCount {
            try Data(repeating: 0x41, count: 100_000)
                .write(to: target.appendingPathComponent("payload\(index).bin"))
        }
        let planned = DirectoryWalker.walk(url: target, inodeSet: InodeSet()).allocatedBytes
        #expect(planned > 0)
        return Fixture(base: base, target: target, plannedBytes: planned)
    }

    private func target(for fixture: Fixture) throws -> DeletionTarget {
        let pathGuard = PathGuard(roots: [fixture.target.deletingLastPathComponent()])
        let validated = try pathGuard.validate(fixture.target)
        let fingerprint = try #require(Fingerprint.capture(at: fixture.target))
        return .path(
            id: "project",
            name: "Project",
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: .regen,
            consequence: "none",
            reclaimableBytes: fixture.plannedBytes
        )
    }

    @Test("A delete that removes every byte but not the emptied directory succeeds")
    func emptiedDirectoryLeftBehindStillSucceeds() async throws {
        let fixture = try makeTarget(under: "Outer")
        let outer = fixture.target.deletingLastPathComponent()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        defer { _ = chflags(outer.path(percentEncoded: false), 0) }

        let plan = try DeletionPlan.single(target(for: fixture))
        #expect(chflags(outer.path(percentEncoded: false), UInt32(UF_IMMUTABLE)) == 0)

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        let outcome = try #require(result.items.first)

        #expect(outcome.status.isSuccess)
        #expect(!outcome.status.isPartialFailure)
        #expect(!result.hasFailures)
        #expect(result.allSucceeded)
        #expect(outcome.freedBytes == fixture.plannedBytes)
        #expect(result.totalFreedBytes == fixture.plannedBytes)

        #expect(FileManager.default.fileExists(atPath: fixture.target.path))
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.target.path).isEmpty)
    }

    @Test("Content recreated during the delete is not counted as a survivor")
    func recreatedContentIsNotASurvivor() async throws {
        let fixture = try makeTarget(under: "Outer", fileCount: 24)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        let writer = RecreatingWriter(directory: fixture.target)
        let plan = try DeletionPlan.single(target(for: fixture))
        writer.start()
        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        writer.stop()

        let survivors = (try? FileManager.default.contentsOfDirectory(atPath: fixture.target.path)) ?? []
        #expect(!survivors.contains { $0.hasPrefix("payload") })

        let outcome = try #require(result.items.first)
        #expect(outcome.status.isSuccess, "reported \(outcome.status) instead")
        #expect(!outcome.status.isPartialFailure)
        #expect(outcome.freedBytes == fixture.plannedBytes)
        #expect(result.totalFreedBytes == fixture.plannedBytes)
    }

    @Test("A delete that removes nothing stays a plain failure")
    func fullyBlockedRemovalIsPlainFailure() async throws {
        let fixture = try makeTarget(under: "Outer")
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        defer { _ = chflags(fixture.target.path(percentEncoded: false), 0) }

        let plan = try DeletionPlan.single(target(for: fixture))
        #expect(chflags(fixture.target.path(percentEncoded: false), UInt32(UF_IMMUTABLE)) == 0)

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        let outcome = try #require(result.items.first)

        #expect(!outcome.status.isSuccess)
        #expect(!outcome.status.isPartialFailure)
        #expect(outcome.freedBytes == 0)
        #expect(result.totalFreedBytes == 0)
        #expect(outcome.status.failureReason?.isEmpty == false)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.target.path).count == 6)
    }

    @Test("The reported freed bytes equal planned minus what is still on disk")
    func freedBytesMatchWhatLeftTheDisk() async throws {
        let fixture = try makeTarget(under: "Outer", fileCount: 10)
        let locked = fixture.target.appendingPathComponent("payload9.bin").path(percentEncoded: false)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        defer { _ = chflags(locked, 0) }

        let plan = try DeletionPlan.single(target(for: fixture))
        #expect(chflags(locked, UInt32(UF_IMMUTABLE)) == 0)

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)
        let outcome = try #require(result.items.first)
        let remaining = DirectoryWalker.walk(url: fixture.target, inodeSet: InodeSet()).allocatedBytes

        #expect(!outcome.status.isSuccess)
        #expect(remaining > 0, "the immutable file must survive")
        #expect(outcome.freedBytes == max(0, fixture.plannedBytes - remaining))
        #expect(result.totalFreedBytes == outcome.freedBytes)
        if outcome.freedBytes > 0 {
            #expect(outcome.status.isPartialFailure)
            #expect(result.partiallyFailedCount == 1)
            #expect(result.failedCount == 0)
            #expect(result.succeededCount == 0)
            #expect(result.hasFailures)
            #expect(!result.allSucceeded)
            let reason = try #require(outcome.status.failureReason)
            #expect(reason.hasPrefix("Partially removed:"))
            #expect(reason.hasSuffix("still on disk."))
            #expect(!reason.contains(".."))
        }
    }

    private final class RecreatingWriter: @unchecked Sendable {
        private let directory: URL
        private let lock = NSLock()
        private var running = false

        init(directory: URL) {
            self.directory = directory
        }

        func start() {
            lock.lock()
            running = true
            lock.unlock()
            Thread.detachNewThread { [self] in
                var index = 0
                while isRunning {
                    try? Data(repeating: 0x5A, count: 32_768)
                        .write(to: directory.appendingPathComponent("live\(index).bin"))
                    index += 1
                }
            }
        }

        func stop() {
            lock.lock()
            running = false
            lock.unlock()
        }

        private var isRunning: Bool {
            lock.lock()
            defer { lock.unlock() }
            return running
        }
    }

    // MARK: - Cancellation

    @Test("A cancelled run records every item as not attempted and touches nothing")
    func cancellationRecordsNotAttempted() async throws {
        let fixture = try makeTarget(under: "Outer", fileCount: 2)
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        let mock = MockSimulatorExecutor()
        let executor = DeletionExecutor(simulatorExecutor: mock)
        let plan = try DeletionPlan.batch([
            target(for: fixture),
            .simulatorErase(udid: "OFF-9", name: "iPhone 17", isBooted: false, consequence: "", reclaimableBytes: 512)
        ])

        let task = Task { await executor.execute(plan) }
        task.cancel()
        let result = await task.value

        #expect(result.items.count == 2)
        #expect(result.failedCount == 0)
        #expect(result.notAttemptedCount == 2)
        #expect(result.totalFreedBytes == 0)
        for item in result.items {
            #expect(item.status.isNotAttempted)
            #expect(item.status.notAttemptedReason == NotAttemptedReason.cancelled.copy)
        }
        #expect(mock.log.commands.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.target.path))
    }
}
