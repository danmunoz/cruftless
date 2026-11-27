@testable import CruftlessCore
import Darwin
import Foundation
import Synchronization
import Testing

@Suite("Android SDK package removal")
struct AndroidSDKPackageRemovalTests {
    @Test("A package whose folder and package.xml agree is captured in the CLI's slash form")
    func identity() throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/35.0.0")
        let identity = try AndroidSDKPackageRemovalIdentity.capture(child: child, sdkRoot: fixture.sdk,
                                                                    protectedPaths: fixture.protection)
        #expect(identity.packagePath == "build-tools;35.0.0")
        #expect(identity.cliName == "build-tools/35.0.0")
        #expect(identity.category == "build-tools")
    }

    @Test("A package.xml naming another package is refused, since the CLI would remove that one")
    func mismatchedMetadata() throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/34.0.0", identity: "build-tools;35.0.0")
        #expect(throws: (any Error).self) {
            try AndroidSDKPackageRemovalIdentity.capture(child: child, sdkRoot: fixture.sdk, protectedPaths: fixture.protection)
        }
    }

    @Test("A package without package.xml, a symlinked folder, the unclassified row and a protected package are refused")
    func refusedShapes() throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let legacy = fixture.sdk.appendingPathComponent("platforms/android-30", isDirectory: true)
        try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
        try Data("Pkg.Path=platforms;android-30\nPkg.Revision=3\n".utf8).write(to: legacy.appendingPathComponent("source.properties"))
        let target = try fixture.addPackage("build-tools/35.0.0")
        let outside = fixture.root.appendingPathComponent("outside", isDirectory: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let link = fixture.sdk.appendingPathComponent("build-tools/36.0.0")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target.url)
        let unclassified = ChildEntry(id: "androidSDK-unclassified", name: "Unclassified", url: fixture.sdk, reclaimableBytes: 1,
                                      staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
        for child in [fixture.child(for: legacy), fixture.child(for: link), unclassified] {
            #expect(throws: (any Error).self) {
                try AndroidSDKPackageRemovalIdentity.capture(child: child, sdkRoot: fixture.sdk, protectedPaths: fixture.protection)
            }
        }
        let protected = ProtectedPaths(customProtectedPaths: [target.url], home: fixture.root)
        #expect(throws: (any Error).self) {
            try AndroidSDKPackageRemovalIdentity.capture(child: target, sdkRoot: fixture.sdk, protectedPaths: protected)
        }
        let foreign = ChildEntry(id: "androidSDK-" + ProtectedPaths.normalize(outside), name: "outside", url: outside,
                                 reclaimableBytes: 1, staleness: StalenessInfo(lastUsedDate: nil), tier: .info, consequence: "")
        #expect(throws: (any Error).self) {
            try AndroidSDKPackageRemovalIdentity.capture(child: foreign, sdkRoot: fixture.sdk, protectedPaths: fixture.protection)
        }
    }

    @Test("Tools set up before versions were checked must be updated before removing a package")
    func outdatedToolsRefused() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/35.0.0")
        let tools = fixture.tools(version: AndroidSDKRemovalFixture.outdated)
        _ = try await tools.setUp()
        await #expect(throws: AndroidSDKPackageRemovalError.updateRequired(installed: AndroidCLIVersion(components: [1, 0, 16_261_425]))) {
            try await fixture.service(tools: tools).prepare(child: child, protectedPaths: fixture.protection)
        }
    }

    @Test("Setup for package removal downloads Google's latest release when the installed copy is older")
    func setupDownloadsLatest() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let downloads = Counter()
        let own = fixture.root.appendingPathComponent("tools/android-cli")
        let tools = AndroidCLITools(
            home: fixture.root, androidUserHome: fixture.registry.deletingLastPathComponent(), sdk: fixture.sdk,
            installDirectory: fixture.root.appendingPathComponent("tools"), candidates: [own, fixture.binary],
            run: { executable, _, _, _ in
                AndroidSDKRemovalFixture.output(executable == own ? AndroidSDKRemovalFixture.latest : AndroidSDKRemovalFixture.outdated)
            },
            download: { source, destination in
                downloads.increment()
                #expect(source == AndroidCLITools.downloadURL)
                try AndroidSDKRemovalFixture.writeExecutable(at: destination)
            }
        )
        let prepared = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        #expect(prepared.executable == own)
        #expect(prepared.version == .minimumForSDKRemoval)
        #expect(downloads.value == 1)
        #expect(try String(contentsOf: fixture.binary, encoding: .utf8) == "test executable")
        guard case .ready = await tools.availability(minimumVersion: .minimumForSDKRemoval) else {
            Issue.record("Expected the downloaded release to be ready")
            return
        }
    }

    @Test("An installed copy that is already current is used without downloading")
    func currentCopyNeedsNoDownload() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let tools = fixture.tools()
        let prepared = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        #expect(prepared.executable == fixture.binary)
    }

    @Test("A system image a virtual device uses is refused; an unused one is allowed")
    func systemImageDependency() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let used = try fixture.addPackage("system-images/android-36/google_apis/arm64-v8a")
        let unused = try fixture.addPackage("system-images/android-35/google_apis/arm64-v8a")
        try fixture.addDevice(named: "Pixel_9", systemImage: "system-images/android-36/google_apis/arm64-v8a/")
        let tools = fixture.tools()
        _ = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        let service = fixture.service(tools: tools)
        await #expect(throws: AndroidSDKPackageRemovalError.usedByDevice("Pixel_9")) {
            try await service.prepare(child: used, protectedPaths: fixture.protection)
        }
        _ = try await service.prepare(child: unused, protectedPaths: fixture.protection)
    }

    @Test("A process running from the package or another SDK manager blocks removal")
    func activity() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("platform-tools")
        let tools = fixture.tools()
        _ = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        let adb = "\(child.url.path)/adb \(child.url.path)/adb -L tcp:5037 fork-server server\n"
        await #expect(throws: AndroidSDKPackageRemovalError.inUse) {
            try await fixture.service(tools: tools, processes: adb).prepare(child: child, protectedPaths: fixture.protection)
        }
        let manager = "java java -cp lib/sdkmanager-classpath.jar com.android.sdklib.tool.sdkmanager.SdkManagerCli\n"
        await #expect(throws: AndroidSDKPackageRemovalError.managerBusy) {
            try await fixture.service(tools: tools, processes: manager).prepare(child: child, protectedPaths: fixture.protection)
        }
    }

    @Test("One reviewed package is removed through the production executor with exact CLI arguments")
    func successfulRemoval() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/35.0.0")
        let neighbor = try fixture.addPackage("build-tools/36.0.0")
        let tools = fixture.tools(onRemove: { arguments in
            #expect(arguments == ["--no-metrics", "--sdk=" + fixture.sdk.path(percentEncoded: false),
                                  "sdk", "remove", "build-tools/35.0.0"])
            TestFileSystem.removeDirectoryRecursively(at: child.url)
            return AndroidSDKRemovalFixture.output("")
        })
        _ = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        let service = fixture.service(tools: tools)
        let request = try await service.prepare(child: child, protectedPaths: fixture.protection)
        let result = try await fixture.executor(service).execute(DeletionPlanner.androidSDKPackage(request, context: fixture.context))
        #expect(result.allSucceeded)
        #expect(result.totalFreedBytes == child.reclaimableBytes)
        #expect(!FileManager.default.fileExists(atPath: child.url.path))
        #expect(FileManager.default.fileExists(atPath: neighbor.url.path))
    }

    @Test("A zero exit that removed nothing is a failure, not a success")
    func zeroExitNoOp() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/35.0.0")
        let tools = fixture.tools(onRemove: { _ in AndroidSDKRemovalFixture.output("None of the specified packages were found.\n") })
        _ = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        let service = fixture.service(tools: tools)
        let request = try await service.prepare(child: child, protectedPaths: fixture.protection)
        let result = try await fixture.executor(service).execute(DeletionPlanner.androidSDKPackage(request, context: fixture.context))
        #expect(result.failedCount == 1)
        #expect(result.totalFreedBytes == 0)
        #expect(result.items.first?.status.failureReason?.contains("did not remove") == true)
    }

    @Test("A removal that stops part way reports what remains", arguments: [Int32(0), Int32(1)])
    func partialRemoval(status: Int32) async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/35.0.0", bytes: 4096)
        let large = child.url.appendingPathComponent("large")
        try Data(repeating: 9, count: 262_144).write(to: large)
        let measured = fixture.child(for: child.url)
        let tools = fixture.tools(onRemove: { _ in
            TestFileSystem.removeFile(at: large)
            return AndroidSDKRemovalFixture.output("", status: status)
        })
        _ = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        let service = fixture.service(tools: tools)
        let request = try await service.prepare(child: measured, protectedPaths: fixture.protection)
        let result = try await fixture.executor(service).execute(DeletionPlanner.androidSDKPackage(request, context: fixture.context))
        #expect(result.partiallyFailedCount == 1)
        #expect(result.totalFreedBytes > 0)
        #expect(result.totalFreedBytes < measured.reclaimableBytes)
        #expect(FileManager.default.fileExists(atPath: child.url.path))
    }

    @Test("Unplanned and multi-package plans are refused before the CLI runs")
    func admission() async throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        let child = try fixture.addPackage("build-tools/35.0.0")
        let removals = Counter()
        let tools = fixture.tools(onRemove: { _ in
            removals.increment()
            return AndroidSDKRemovalFixture.output("")
        })
        _ = try await tools.setUp(minimumVersion: .minimumForSDKRemoval)
        let service = fixture.service(tools: tools)
        let target = try await DeletionTarget.androidSDKPackageDelete(service.prepare(child: child, protectedPaths: fixture.protection))
        let executor = fixture.executor(service)
        let single = await executor.execute(.single(target, affectedLocationIds: [LocationCatalog.androidSDK.id]))
        #expect(single.notAttemptedCount == 1)
        let batch = await executor.execute(.plannedBatch([target, target], affectedLocationIds: [LocationCatalog.androidSDK.id]))
        #expect(batch.notAttemptedCount == 2)
        let wrongLocation = await executor.execute(.plannedBatch([target], affectedLocationIds: [LocationCatalog.androidAVDs.id]))
        #expect(wrongLocation.notAttemptedCount == 1)
        #expect(removals.value == 0)
        #expect(FileManager.default.fileExists(atPath: child.url.path))
    }

    @Test("The CLI's .sdk index folder keeps the inventory complete")
    func sdkIndexFolderIsKnown() throws {
        let fixture = try AndroidSDKRemovalFixture()
        defer { fixture.cleanUp() }
        try fixture.addPackage("build-tools/35.0.0")
        try FileManager.default.createDirectory(at: fixture.sdk.appendingPathComponent(".sdk/objects"), withIntermediateDirectories: true)
        let scan = DrillDownProvider.androidSDKPackages(in: [fixture.sdk])
        #expect(scan.issue == nil)
    }
}

private final class Counter: Sendable {
    private let count = Mutex(0)

    var value: Int {
        count.withLock { $0 }
    }

    func increment() {
        count.withLock { $0 += 1 }
    }
}
