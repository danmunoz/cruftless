import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionExecutor space-settle wait")
struct DeletionExecutorSettleTests {
    private static let baseline: Int64 = 100_000_000_000
    private static let fourGigabytes: Int64 = 4_000_000_000

    @Test("A path delete reports mutating progress and never waits for space")
    func pathDeleteSkipsSettleWait() async throws {
        let tempBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempBase, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: tempBase) }

        let targetFile = tempBase.appendingPathComponent("build.artifact")
        try "artifact data".write(to: targetFile, atomically: true, encoding: .utf8)

        let validated = try PathGuard(roots: [tempBase]).validate(targetFile)
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

        let capacity = ScriptedCapacity([Self.baseline])
        let sleeps = SleepCounter()
        let recorder = ProgressRecorder()
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            capacitySampler: { capacity.next() },
            settleSleep: { try await sleeps.tick() }
        )

        let result = await executor.execute(DeletionPlan.plannedSingle(target)) { recorder.record($0) }

        #expect(result.allSucceeded)
        #expect(sleeps.isEmpty)
        #expect(capacity.samplesTaken == 0)
        #expect(recorder.values == [DeletionProgress(verb: .clear, targetName: "artifact", phase: .mutating)])
        #expect(!FileManager.default.fileExists(atPath: targetFile.path))
    }

    @Test("An erase reports both phases and settles when the space arrives")
    func eraseReportsBothPhasesAndSettles() async {
        let capacity = ScriptedCapacity([Self.baseline, Self.baseline + Self.fourGigabytes])
        let sleeps = SleepCounter()
        let recorder = ProgressRecorder()
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            capacitySampler: { capacity.next() },
            settleSleep: { try await sleeps.tick() }
        )

        let target = DeletionTarget.simulatorErase(
            udid: "SET-1",
            name: "iPhone 17 Pro",
            isBooted: false,
            consequence: "",
            reclaimableBytes: Self.fourGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target)) { recorder.record($0) }

        #expect(result.allSucceeded)
        #expect(result.items[0].spaceSettle == .settled)
        #expect(recorder.values == [
            DeletionProgress(verb: .erase, targetName: "iPhone 17 Pro", phase: .mutating),
            DeletionProgress(verb: .erase, targetName: "iPhone 17 Pro", phase: .waitingForSpace)
        ])
        #expect(sleeps.isEmpty == false)
    }

    @Test("A delete settles before reporting success")
    func deleteSettlesBeforeSuccess() async {
        let capacity = ScriptedCapacity([Self.baseline, Self.baseline + Self.fourGigabytes])
        let sleeps = SleepCounter()
        let recorder = ProgressRecorder()
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            capacitySampler: { capacity.next() },
            settleSleep: { try await sleeps.tick() }
        )

        let target = DeletionTarget.simulatorDelete(
            udid: "SET-2",
            name: "iPhone 17 Pro",
            isBooted: false,
            consequence: "",
            reclaimableBytes: Self.fourGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target)) { recorder.record($0) }

        #expect(result.allSucceeded)
        #expect(result.items[0].spaceSettle == .settled)
        #expect(recorder.values == [
            DeletionProgress(verb: .delete, targetName: "iPhone 17 Pro", phase: .mutating),
            DeletionProgress(verb: .delete, targetName: "iPhone 17 Pro", phase: .waitingForSpace)
        ])
    }

    @Test("A runtime delete waits for space after the removal is confirmed")
    func runtimeDeleteSettlesAfterRemoval() async {
        let sevenPointEightGigabytes: Int64 = 7_800_000_000
        let capacity = ScriptedCapacity([Self.baseline, Self.baseline + sevenPointEightGigabytes])
        let sleeps = SleepCounter()
        let recorder = ProgressRecorder()
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            capacitySampler: { capacity.next() },
            settleSleep: { try await sleeps.tick() }
        )

        let target = DeletionTarget.runtimeDelete(
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-4",
            name: "iOS 17.4",
            consequence: "",
            reclaimableBytes: sevenPointEightGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target)) { recorder.record($0) }

        #expect(result.allSucceeded)
        #expect(result.items[0].spaceSettle == .settled)
        #expect(recorder.values == [
            DeletionProgress(verb: .remove, targetName: "iOS 17.4", phase: .mutating),
            DeletionProgress(verb: .remove, targetName: "iOS 17.4", phase: .waitingForSpace)
        ])
    }

    @Test("A capped settle still reports the mutation as a success")
    func cappedSettleStillSucceeds() async {
        let capacity = ScriptedCapacity([Self.baseline])
        let sleeps = SleepCounter()
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            capacitySampler: { capacity.next() },
            settleSleep: { try await sleeps.tick() }
        )

        let target = DeletionTarget.simulatorErase(
            udid: "SET-3",
            name: "iPhone 17 Pro",
            isBooted: false,
            consequence: "",
            reclaimableBytes: Self.fourGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(!result.hasFailures)
        #expect(result.items[0].freedBytes == Self.fourGigabytes)
        #expect(result.items[0].spaceSettle == .capped)
        #expect(result.items[0].status.failureReason == nil)
        #expect(sleeps.count == SpaceSettleDetector.capSamples(forExpectedBytes: Self.fourGigabytes) - 1)
    }

    @Test("An erase whose device directory never shrinks still succeeds")
    func unconfirmedEraseStillSucceeds() async throws {
        let deviceDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: deviceDirectory, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: deviceDirectory) }

        let blob = deviceDirectory.appendingPathComponent("blob.bin")
        try Data(count: 65_000_000).write(to: blob, options: .atomic)

        let capacity = ScriptedCapacity([Self.baseline])
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            deviceDirectory: { _ in deviceDirectory },
            capacitySampler: { capacity.next() }
        )

        let target = DeletionTarget.simulatorErase(
            udid: "SET-4",
            name: "iPhone 17 Pro",
            isBooted: false,
            consequence: "",
            reclaimableBytes: Self.fourGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(result.items[0].spaceSettle == .capped)
        #expect(FileManager.default.fileExists(atPath: deviceDirectory.path))
        #expect(FileManager.default.fileExists(atPath: blob.path))
    }

    @Test("An erase with no device directory to check still succeeds")
    func missingDeviceDirectoryStillSucceeds() async {
        let capacity = ScriptedCapacity([Self.baseline, Self.baseline + Self.fourGigabytes])
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: MockSimulatorExecutor(),
            capacitySampler: { capacity.next() }
        )

        let target = DeletionTarget.simulatorErase(
            udid: "SET-5",
            name: "iPhone 17 Pro",
            isBooted: false,
            consequence: "",
            reclaimableBytes: Self.fourGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.allSucceeded)
        #expect(result.items[0].spaceSettle == .settled)
    }

    @Test("A failed erase never reaches the settle wait")
    func failedEraseSkipsSettle() async {
        var mock = MockSimulatorExecutor()
        mock.shouldFailErase = true

        let capacity = ScriptedCapacity([Self.baseline])
        let sleeps = SleepCounter()
        let recorder = ProgressRecorder()
        let executor = DeletionExecutor.testExecutor(
            simulatorExecutor: mock,
            capacitySampler: { capacity.next() },
            settleSleep: { try await sleeps.tick() }
        )

        let target = DeletionTarget.simulatorErase(
            udid: "SET-6",
            name: "iPhone 17 Pro",
            isBooted: false,
            consequence: "",
            reclaimableBytes: Self.fourGigabytes
        )
        let result = await executor.execute(DeletionPlan.single(target)) { recorder.record($0) }

        #expect(result.failedCount == 1)
        #expect(sleeps.isEmpty)
        #expect(capacity.samplesTaken == 1)
        #expect(!recorder.values.contains { $0.phase == .waitingForSpace })
    }
}
