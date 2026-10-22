@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("Android AVD removal")
struct AndroidAVDRemovalTests {
    @Test("Ordinary Pixel metadata is supported while paths and user protection remain guarded")
    func identity() throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        _ = try AndroidAVDRemovalIdentity.capture(child: fixture.child, registryRoot: fixture.registry, protectedPaths: fixture.protection)
        #expect(throws: (any Error).self) {
            try AndroidAVDRemovalIdentity.capture(child: fixture.child, registryRoot: fixture.root, protectedPaths: fixture.protection)
        }
        #expect(throws: (any Error).self) {
            try AndroidAVDRemovalIdentity.capture(child: fixture.child, registryRoot: fixture.registry,
                                                  protectedPaths: ProtectedPaths(
                                                      customProtectedPaths: [fixture.directory],
                                                      home: fixture.root
                                                  ))
        }
        try Data("AvdId=Probe\nsdcard.path=/other/data.img\n".utf8).write(to: fixture.directory.appendingPathComponent("config.ini"))
        #expect(throws: (any Error).self) {
            try AndroidAVDRemovalIdentity.capture(child: fixture.child, registryRoot: fixture.registry, protectedPaths: fixture.protection)
        }
    }

    @Test("Ambiguous registry syntax and duplicate aliases are refused")
    func ambiguousRegistration() throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let metadata = fixture.registry.appendingPathComponent("Probe.ini")
        let original = try String(contentsOf: metadata, encoding: .utf8)
        try Data((original + "path=/other/device\\\n").utf8).write(to: metadata)
        #expect(throws: (any Error).self) {
            try AndroidAVDRemovalIdentity.capture(child: fixture.child, registryRoot: fixture.registry, protectedPaths: fixture.protection)
        }
        try Data(original.utf8).write(to: metadata)
        try Data("path=\(fixture.registry.appendingPathComponent("Alias.avd").path)\npath.rel=Probe.avd\n".utf8)
            .write(to: fixture.registry.appendingPathComponent("Alias.ini"))
        #expect(throws: (any Error).self) {
            try AndroidAVDRemovalIdentity.capture(child: fixture.child, registryRoot: fixture.registry, protectedPaths: fixture.protection)
        }
    }

    @Test("Checking availability neither probes nor installs; setup is separate and reusable")
    func explicitPreparation() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let calls = AndroidProbeCalls()
        let tools = fixture.tools(run: { _, args, _, _ in
            await calls.record(args)
            return BoundedProcess.Output(status: 0, stdoutData: Data("1.0.16625370\n".utf8), stderrData: Data())
        })
        guard case .setupRequired = await tools.availability() else { Issue.record("Expected setup consent")
            return
        }
        #expect(await calls.isEmpty)
        _ = try await tools.setUp()
        guard case .ready = await tools.availability() else { Issue.record("Expected prepared tools")
            return
        }
        #expect(await calls.count == 1)
        let reloaded = fixture.tools()
        guard case .ready = await reloaded.availability() else { Issue.record("Setup should survive relaunch")
            return
        }
    }

    @Test("Missing-tool refusal does not download until setup is explicitly requested")
    func missingTool() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let calls = AndroidProbeCalls()
        let tools = fixture.tools(candidates: [], download: { _, _ in
            await calls.record(["download"])
            throw AndroidAVDRemovalError.refused("Network unavailable")
        })
        await #expect(throws: (any Error).self) {
            try await fixture.service(tools: tools).prepare(child: fixture.child, protectedPaths: fixture.protection)
        }
        #expect(await calls.isEmpty)
        await #expect(throws: (any Error).self) { try await tools.setUp() }
        #expect(await calls.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))
        guard case .setupRequired = await tools.availability() else { Issue.record("Failed setup must not become ready")
            return
        }
    }

    @Test("One planner-authorized device is removed through the production executor")
    func successfulRemoval() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let neighbor = fixture.registry.appendingPathComponent("Neighbor.avd")
        try FileManager.default.createDirectory(at: neighbor, withIntermediateDirectories: true)
        let tools = fixture.tools(run: { _, args, environment, _ in
            if args.contains("remove") {
                #expect(args == ["--no-metrics", "--sdk=" + fixture.root.appendingPathComponent("sdk").path,
                                 "emulator", "remove", "Probe"])
                #expect(ProtectedPaths.normalize(URL(fileURLWithPath: environment["ANDROID_USER_HOME"] ?? "/"))
                    == ProtectedPaths.normalize(fixture.registry.deletingLastPathComponent()))
                TestFileSystem.removeDirectoryRecursively(at: fixture.directory)
                TestFileSystem.removeFile(at: fixture.registry.appendingPathComponent("Probe.ini"))
            }
            return BoundedProcess.Output(status: 0, stdoutData: Data("1.0.16625370\n".utf8), stderrData: Data())
        })
        _ = try await tools.setUp()
        let service = fixture.service(tools: tools)
        let request = try await service.prepare(child: fixture.child, protectedPaths: fixture.protection)
        let plan = try DeletionPlanner.androidAVD(request, context: PlanningContext(protectedPaths: fixture.protection))
        let policy = PolicyGenerationAuthority()
        policy.update(to: 0, readOnlyLocationIDs: [LocationCatalog.androidAVDs.id])
        let executor = DeletionExecutor(androidAVDRemoval: service, policyGenerationAuthority: policy)
        let result = await executor.execute(plan)
        #expect(result.allSucceeded)
        #expect(FileManager.default.fileExists(atPath: neighbor.path))
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("An emulator starting during Review is refused before invoking removal")
    func activityRecheck() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let state = AndroidProbeCalls()
        let tools = fixture.tools()
        _ = try await tools.setUp()
        let service = fixture.service(tools: tools, activity: { _, _, _, _ in
            let active = await !(state.isEmpty)
            return BoundedProcess.Output(
                status: 0,
                stdoutData: Data((active ? "qemu-system-aarch64 qemu-system-aarch64 -avd Probe\n" : "launchd launchd\n").utf8),
                stderrData: Data()
            )
        })
        let request = try await service.prepare(child: fixture.child, protectedPaths: fixture.protection)
        let plan = try DeletionPlanner.androidAVD(request, context: PlanningContext(protectedPaths: fixture.protection))
        await state.record(["active"])
        let result = await DeletionExecutor(androidAVDRemoval: service).execute(plan)
        #expect(result.failedCount == 1)
        #expect(result.items.first?.status.failureReason?.contains("active") == true)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Policy changes during asynchronous activity checks prevent removal")
    func policyRecheck() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let policy = PolicyGenerationAuthority()
        let calls = AndroidProbeCalls()
        let tools = fixture.tools()
        _ = try await tools.setUp()
        let service = fixture.service(tools: tools, activity: { _, _, _, _ in
            await calls.record(["activity"])
            if await calls.count > 1 { policy.update(to: 1) }
            return BoundedProcess.Output(status: 0, stdoutData: Data("launchd launchd\n".utf8), stderrData: Data())
        })
        let request = try await service.prepare(child: fixture.child, protectedPaths: fixture.protection)
        let plan = try DeletionPlanner.androidAVD(request, context: PlanningContext(protectedPaths: fixture.protection))
        let result = await DeletionExecutor(androidAVDRemoval: service, policyGenerationAuthority: policy).execute(plan)
        #expect(result.failedCount == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Unverified and multi-device plans are refused")
    func admission() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let tools = fixture.tools()
        _ = try await tools.setUp()
        let service = fixture.service(tools: tools)
        let request = try await service.prepare(child: fixture.child, protectedPaths: fixture.protection)
        let target = DeletionTarget.androidAVDDelete(request)
        let executor = DeletionExecutor(androidAVDRemoval: service)
        let single = await executor.execute(.single(target, affectedLocationIds: [LocationCatalog.androidAVDs.id]))
        #expect(single.notAttemptedCount == 1)
        let batch = await executor.execute(.plannedBatch([target, target], affectedLocationIds: [LocationCatalog.androidAVDs.id]))
        #expect(batch.notAttemptedCount == 2)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))
    }

    @Test("Unknown activity and a held emulator lock are refused")
    func unknownAndLocked() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let tools = fixture.tools()
        _ = try await tools.setUp()
        let unknown = fixture.service(tools: tools, activity: { _, _, _, _ in
            BoundedProcess.Output(status: 1, stdoutData: Data(), stderrData: Data())
        })
        await #expect(throws: (any Error).self) { try await unknown.prepare(child: fixture.child, protectedPaths: fixture.protection) }
        let descriptor = open(fixture.directory.appendingPathComponent("multiinstance.lock").path, O_CREAT | O_RDWR, 0o600)
        defer { close(descriptor) }
        #expect(flock(descriptor, LOCK_EX | LOCK_NB) == 0)
        await #expect(throws: (any Error).self) {
            try await fixture.service(tools: tools).prepare(child: fixture.child, protectedPaths: fixture.protection)
        }
    }

    @Test("Zero-exit partial deletion and interruption retain remaining bytes", arguments: [false, true])
    func partialRemoval(interrupted: Bool) async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let calls = AndroidProbeCalls()
        let tools = fixture.tools(run: { _, args, _, _ in
            if args.contains("remove") {
                await calls.record(args)
                TestFileSystem.removeFile(at: fixture.registry.appendingPathComponent("Probe.ini"))
                if interrupted { throw BoundedProcess.RunError.timedOut("test interruption") }
            }
            return BoundedProcess.Output(status: 0, stdoutData: Data("1.0.16625370\n".utf8), stderrData: Data())
        })
        _ = try await tools.setUp()
        let service = fixture.service(tools: tools)
        let request = try await service.prepare(child: fixture.child, protectedPaths: fixture.protection)
        let plan = try DeletionPlanner.androidAVD(request, context: PlanningContext(protectedPaths: fixture.protection))
        let result = await DeletionExecutor(androidAVDRemoval: service).execute(plan)
        #expect(result.partiallyFailedCount == 1)
        #expect(result.totalFreedBytes == 0)
        #expect(await calls.count == 1)
        #expect(FileManager.default.fileExists(atPath: fixture.directory.path))
    }
}

private actor AndroidProbeCalls {
    private var calls: [[String]] = []
    var count: Int {
        calls.count
    }

    var isEmpty: Bool {
        calls.isEmpty
    }

    func record(_ arguments: [String]) {
        calls.append(arguments)
    }
}
