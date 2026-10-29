@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("Disposable official Android CLI integration")
struct AndroidAVDLiveRemovalTests {
    @Test("Production installer and executor remove only owned disposable devices",
          .enabled(if: ProcessInfo.processInfo.environment["CRUFTLESS_ANDROID_LIVE_TESTS"] == "1"))
    func officialCLI() async throws {
        let fixture = try AndroidRemovalFixture()
        defer { fixture.cleanUp() }
        let install = fixture.root.appendingPathComponent("tools", isDirectory: true)
        let tools = AndroidCLITools(home: fixture.root, androidUserHome: fixture.registry.deletingLastPathComponent(),
                                    sdk: fixture.root.appendingPathComponent("sdk", isDirectory: true), installDirectory: install,
                                    candidates: [install.appendingPathComponent("android-cli")])
        try FileManager.default.createDirectory(at: fixture.root.appendingPathComponent("sdk"), withIntermediateDirectories: true)
        let neighbor = try fixture.addDevice(named: "Neighbor")
        let shared = fixture.root.appendingPathComponent("sdk/shared-system-image")
        try Data("shared SDK sentinel".utf8).write(to: shared)
        guard case .setupRequired = await tools.availability() else { Issue.record("Expected consent before setup")
            return
        }
        _ = try await tools.setUp()
        let service = AndroidAVDRemoval(tools: tools, registryRoot: fixture.registry)
        let executor = DeletionExecutor(androidAVDRemoval: service)
        let context = PlanningContext(protectedPaths: fixture.protection)
        let request = try await service.prepare(child: fixture.child, protectedPaths: fixture.protection)
        let result = try await executor.execute(DeletionPlanner.androidAVD(request, context: context))
        #expect(result.allSucceeded)
        #expect(!FileManager.default.fileExists(atPath: fixture.directory.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.url.path))
        #expect(try Data(contentsOf: shared) == Data("shared SDK sentinel".utf8))

        let partial = try fixture.addDevice(named: "Partial")
        let immutable = partial.url.appendingPathComponent("data")
        #expect(chflags(immutable.path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(immutable.path, 0) }
        let partialRequest = try await service.prepare(child: partial, protectedPaths: fixture.protection)
        let partialResult = try await executor.execute(DeletionPlanner.androidAVD(partialRequest, context: context))
        #expect(partialResult.partiallyFailedCount == 1)
        #expect(!FileManager.default.fileExists(atPath: fixture.registry.appendingPathComponent("Partial.ini").path))
        #expect(FileManager.default.fileExists(atPath: immutable.path))
        #expect(!partialResult.allSucceeded)

        let timeout = try fixture.addDevice(named: "Timeout")
        let bounded = AndroidAVDRemoval(tools: tools, registryRoot: fixture.registry, removalTimeout: .milliseconds(1))
        let timeoutRequest = try await bounded.prepare(child: timeout, protectedPaths: fixture.protection)
        let timeoutResult = try await DeletionExecutor(androidAVDRemoval: bounded)
            .execute(DeletionPlanner.androidAVD(timeoutRequest, context: context))
        #expect(!timeoutResult.allSucceeded)
        #expect(FileManager.default.fileExists(atPath: timeout.url.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.url.path))
        #expect(try Data(contentsOf: shared) == Data("shared SDK sentinel".utf8))
    }
}
