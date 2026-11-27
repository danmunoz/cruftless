@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("Disposable official Android CLI SDK removal")
struct AndroidSDKLiveRemovalTests {
    /// Clones the newest installed build-tools into a disposable SDK, so the real CLI sees genuine package metadata.
    @Test("Google's latest CLI removes one cloned package, reports a locked one as partial, and leaves neighbours alone",
          .enabled(if: ProcessInfo.processInfo.environment["CRUFTLESS_ANDROID_LIVE_TESTS"] == "1"))
    func officialCLI() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let source = try #require(RootResolver.androidSDKRoots().first?.appendingPathComponent("build-tools"))
        let versions = try FileManager.default.contentsOfDirectory(atPath: source.path)
            .filter { !$0.hasPrefix(".") }.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
        try #require(versions.count >= 2, "Needs two installed build-tools versions to clone")
        let tools = fixture.sdk.appendingPathComponent("build-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: tools, withIntermediateDirectories: true)
        for version in versions.suffix(2) {
            try FileManager.default.copyItem(at: source.appendingPathComponent(version), to: tools.appendingPathComponent(version))
        }
        let target = fixture.child(for: tools.appendingPathComponent(versions[versions.count - 2], isDirectory: true))
        let locked = fixture.child(for: tools.appendingPathComponent(versions[versions.count - 1], isDirectory: true))

        let install = fixture.root.appendingPathComponent("tools", isDirectory: true)
        let cli = AndroidCLITools(home: fixture.root, androidUserHome: fixture.registry.deletingLastPathComponent(), sdk: fixture.sdk,
                                  installDirectory: install, candidates: [install.appendingPathComponent("android-cli")])
        let prepared = try await cli.setUp(minimumVersion: .minimumForSDKRemoval)
        #expect(prepared.version.map { $0 >= .minimumForSDKRemoval } == true)
        let service = AndroidSDKPackageRemoval(tools: cli, avdRoots: [fixture.registry])
        let executor = fixture.executor(service)

        let request = try await service.prepare(child: target, protectedPaths: fixture.protection)
        let result = try await executor.execute(DeletionPlanner.androidSDKPackage(request, context: fixture.context))
        #expect(result.allSucceeded)
        #expect(!FileManager.default.fileExists(atPath: target.url.path))
        #expect(FileManager.default.fileExists(atPath: locked.url.path))

        let immutable = try #require(FileManager.default.subpathsOfDirectory(atPath: locked.url.path)
            .map { locked.url.appendingPathComponent($0) }
            .last { !$0.hasDirectoryPath && $0.lastPathComponent != "package.xml" })
        #expect(chflags(immutable.path, UInt32(UF_IMMUTABLE)) == 0)
        defer { chflags(immutable.path, 0) }
        let lockedRequest = try await service.prepare(child: locked, protectedPaths: fixture.protection)
        let lockedResult = try await executor.execute(DeletionPlanner.androidSDKPackage(lockedRequest, context: fixture.context))
        #expect(!lockedResult.allSucceeded)
        #expect(FileManager.default.fileExists(atPath: immutable.path))
    }
}
