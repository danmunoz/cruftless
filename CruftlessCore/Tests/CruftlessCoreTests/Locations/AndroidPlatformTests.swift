@testable import CruftlessCore
import Foundation
import Testing

private actor CountingSimulatorExecutor: SimulatorCommandExecuting {
    private(set) var calls = 0

    func shutdownSimulator(udid: String) async throws { calls += 1 }
    func eraseSimulator(udid: String) async throws { calls += 1 }
    func deleteSimulator(udid: String) async throws { calls += 1 }
    func deleteRuntime(identifier: String) async throws { calls += 1 }
}

@Suite("Android platform selection and discovery")
struct AndroidPlatformTests {
    @Test("Missing, empty, or unknown selections migrate to Apple; known values survive unknown ones")
    func selectionMigration() {
        #expect(PlatformSelection.migrate(nil) == .appleOnly)
        #expect(PlatformSelection.migrate([]) == .appleOnly)
        #expect(PlatformSelection.migrate(["future"]) == .appleOnly)
        #expect(PlatformSelection.migrate(["future", "android"]) == .androidOnly)
        #expect(PlatformSelection.migrate(["android", "apple"]).platforms == Set(DevelopmentPlatform.allCases))
    }

    @Test("Every Android inventory location is read-only and excluded from reclaimable totals")
    func androidLocationsAreReadOnly() {
        let locations = LocationCatalog.all.filter { $0.platform == .android }
        #expect(locations.count == 4)
        #expect(locations.allSatisfy { $0.mutationPolicy == .readOnly && $0.tier == .info })
        #expect(PlatformSelection.androidOnly.catalog().locations == locations)
    }

    @Test("Read-only mutation policy excludes a deceptively deletable tier from cleanable totals")
    func readOnlyCapabilityOwnsTotals() {
        let location = TrackedLocation(
            id: "readOnlyTotal",
            platform: .android,
            title: "Read-only fixture",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: false,
            stalenessSource: .topLevelMtime,
            mutationPolicy: .readOnly,
            resolveRoots: { [] }
        )
        let entry = InventoryEntry.sized(
            location: location,
            reclaimableBytes: 10_000,
            staleness: StalenessInfo(lastUsedDate: nil),
            roots: []
        )
        let inventory = Inventory(
            entries: [entry],
            capacity: VolumeCapacity(totalBytes: 100_000, freeBytes: 50_000, purgeableBytes: 0, usedBytes: 50_000)
        )

        #expect(inventory.reclaimableBytes == 0)
    }

    @Test("SDK and AVD roots follow explicit environment precedence")
    func sdkAndAVDRootResolution() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }

        let sdk = fixture.directory("sdk")
        let avdHome = fixture.directory("avds")
        let sdkRoots = RootResolver.androidSDKRoots(
            home: fixture.home,
            environment: ["ANDROID_HOME": sdk.path, "ANDROID_SDK_ROOT": sdk.path]
        )
        let avdRoots = RootResolver.androidAVDRoots(
            home: fixture.home,
            environment: ["ANDROID_AVD_HOME": avdHome.path, "ANDROID_USER_HOME": "/ignored"]
        )

        #expect(sdkRoots.map(ProtectedPaths.normalize) == [ProtectedPaths.normalize(sdk)])
        #expect(avdRoots.map(ProtectedPaths.normalize) == [ProtectedPaths.normalize(avdHome)])
        #expect(RootResolver.androidSDKRoots(
            home: fixture.home,
            environment: ["ANDROID_HOME": sdk.path, "ANDROID_SDK_ROOT": fixture.directory("other-sdk").path]
        ).isEmpty)
        #expect(RootResolver.androidAVDRoots(home: fixture.home, environment: ["ANDROID_AVD_HOME": "relative"]).isEmpty)
    }

    @Test("Studio system discovery accepts versioned stable and preview roots only")
    func studioRootsUseVersionedNames() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let parent = fixture.directory("Library/Caches/Google")
        _ = fixture.directory("Library/Caches/Google/AndroidStudio2025.1")
        _ = fixture.directory("Library/Caches/Google/AndroidStudioPreview2025.2")
        _ = fixture.directory("Library/Caches/Google/AndroidStudioBackup")
        _ = fixture.directory("Library/Caches/Google/AndroidStudio2025.1/plugins")

        let roots = RootResolver.androidStudioSystemRoots(home: fixture.home)
        #expect(roots.count == 2)
        #expect(roots.allSatisfy { ProtectedPaths.normalize($0).hasPrefix(ProtectedPaths.normalize(parent) + "/") })
    }

    @Test("Studio custom system paths are boundedly parsed and reported as incomplete")
    func studioCustomSystemPathIsReported() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        _ = fixture.directory("Library/Caches/Google/AndroidStudio2025.1")
        let config = fixture.directory("Library/Application Support/Google/AndroidStudio2025.1")
        let properties = config.appendingPathComponent("idea.properties")
        let customPath = fixture.directory("custom-studio-system")
        try "idea.system.path=\(customPath.path)\n".write(to: properties, atomically: true, encoding: .utf8)

        #expect(RootResolver.androidStudioSystemIssue(home: fixture.home) != nil)
        let protected = ProtectedPaths(customProtectedPaths: [], home: fixture.home)
        #expect(protected.isProtected(customPath))

        try "# comment\nidea.system.path=$USER_HOME$/custom\n".write(to: properties, atomically: true, encoding: .utf8)
        #expect(RootResolver.androidStudioSystemIssue(home: fixture.home) != nil)

        try "idea.system.path=\(fixture.home.path)/Library/Caches/Google/AndroidStudio2025.1\n"
            .write(to: properties, atomically: true, encoding: .utf8)
        #expect(RootResolver.androidStudioSystemIssue(home: fixture.home) == nil)
    }

    @Test("Read-only policy blocks every path planner route even with a deletable presentation tier")
    func readOnlyPolicyCannotBeBypassed() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let root = fixture.directory("android-system")
        let childURL = root.appendingPathComponent("cache", isDirectory: true)
        _ = fixture.directory("android-system/cache")
        let location = TrackedLocation(
            id: "readOnlyFixture",
            platform: .android,
            title: "Android fixture",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            mutationPolicy: .readOnly,
            resolveRoots: { [root] }
        )
        let entry = InventoryEntry.sized(
            location: location,
            reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: nil),
            roots: [RootSize(url: root, allocatedBytes: 1)]
        )
        let child = ChildEntry(
            id: "child",
            name: "cache",
            url: childURL,
            reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: nil),
            tier: .regen,
            consequence: "Fixture"
        )

        #expect(throws: DeletionPlanningError.readOnlyLocation(title: location.title)) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.readOnlyLocation(title: location.title)) {
            try DeletionPlanner.child(child, in: location, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.readOnlyLocation(title: location.title)) {
            try DeletionPlanner.children([child], in: location, context: PlanningContext())
        }
    }

    @Test("Executor rejects a plan from an older policy generation before mutation")
    func stalePlanIsRejectedAtAdmission() async throws {
        let simulator = CountingSimulatorExecutor()
        let authority = PolicyGenerationAuthority(initialGeneration: 1)
        let executor = DeletionExecutor(simulatorExecutor: simulator, policyGenerationAuthority: authority)
        let target = DeletionTarget.runtimeDelete(
            identifier: "runtime-id",
            name: "Runtime",
            consequence: "Fixture",
            reclaimableBytes: 1
        )
        let plan = DeletionPlan.single(target, policyGeneration: 0)

        let result = await executor.execute(plan)

        #expect(result.items.first?.status.notAttemptedReason == NotAttemptedReason.policyChanged.copy)
        #expect(await simulator.calls == 0)
    }

    @Test("AVD path metadata protects redirected data locations")
    func redirectedAVDDataIsProtected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let avdRoot = fixture.directory(".android/avd")
        let redirected = fixture.directory("emulator-data/Pixel.avd")
        try "path=\(redirected.path)\npath.rel=avd/Pixel.avd\n"
            .write(to: avdRoot.appendingPathComponent("Pixel.ini"), atomically: true, encoding: .utf8)

        let paths = RootResolver.androidAVDRedirectPaths(
            home: fixture.home,
            environment: [:]
        )

        #expect(paths.contains { ProtectedPaths.normalize($0) == ProtectedPaths.normalize(redirected) })
        #expect(RootResolver.androidAVDMetadataIssue(root: avdRoot, home: fixture.home) != nil)
    }

    @Test("Executor rejects a raw path plan with caller-controlled location identity")
    func executorRejectsReadOnlyCatalogTarget() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let root = fixture.directory("read-only-root")
        let child = root.appendingPathComponent("package", isDirectory: true)
        _ = fixture.directory("read-only-root/package")
        let policy = ProtectedPaths(customProtectedPaths: [], home: fixture.home)
        let pathGuard = PathGuard(roots: [root], protectedPaths: policy)
        let authority = PolicyGenerationAuthority()
        authority.update(to: 0, readOnlyLocationIDs: ["androidSDK"])
        let executor = DeletionExecutor(policyGenerationAuthority: authority)
        let target = DeletionTarget.path(
            id: "caller-chosen-id",
            name: "Package",
            validatedPath: try pathGuard.validate(child),
            fingerprint: try #require(Fingerprint.capture(at: child)),
            tier: .regen,
            consequence: "Fixture",
            reclaimableBytes: 1
        )

        let result = await executor.execute(DeletionPlan.single(target))

        #expect(result.items.first?.status.notAttemptedReason == NotAttemptedReason.unverifiedPlan.copy)
        #expect(FileManager.default.fileExists(atPath: child.path(percentEncoded: false)))
    }

    @Test("Persistent Android state is denied by PathGuard even with caller-supplied roots")
    func persistentAndroidRootsStayProtected() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let policy = ProtectedPaths(customProtectedPaths: [], home: home)
        let targets = [
            home.appendingPathComponent(".android/avd/Pixel.avd/userdata.img"),
            home.appendingPathComponent(".gradle/caches/modules-2/files-2.1"),
            home.appendingPathComponent(".gradle/init.d/company.gradle"),
            home.appendingPathComponent("Library/Android/sdk/platforms/android-35"),
            home.appendingPathComponent("Library/Caches/Google/AndroidStudio2025.1/system/localHistory")
        ]

        for target in targets {
            let guardInstance = PathGuard(roots: [target.deletingLastPathComponent()], protectedPaths: policy)
            #expect(throws: PathGuardError.self) { try guardInstance.validate(target) }
            #expect(policy.isProtected(target))
        }
    }

    private struct Fixture {
        let home: URL
        let base: URL

        init() throws {
            base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
                .appendingPathComponent(".cruftless-android-test-\(UUID().uuidString)", isDirectory: true)
            home = base
            try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        }

        func directory(_ relativePath: String) -> URL {
            let url = base.appendingPathComponent(relativePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func remove() {
            TestFileSystem.removeDirectoryRecursively(at: base)
        }
    }
}

extension AndroidPlatformTests {
    @Test("Executor refuses a planner-authorized target for a hidden read-only location")
    func hiddenReadOnlyLocationRemainsProtected() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let root = fixture.directory("read-only-root")
        let child = fixture.directory("read-only-root/package")
        let authority = PolicyGenerationAuthority()
        authority.update(to: 0, readOnlyLocationIDs: ["androidSDK"])
        let policy = ProtectedPaths(customProtectedPaths: [], home: fixture.home)
        let pathGuard = PathGuard(roots: [root], protectedPaths: policy)
        let target = DeletionTarget.path(
            id: "androidSDK-package",
            name: "Package",
            validatedPath: try pathGuard.validate(child),
            fingerprint: try #require(Fingerprint.capture(at: child)),
            tier: .regen,
            consequence: "Fixture",
            reclaimableBytes: 1
        )
        let plan = DeletionPlan.plannedSingle(target, affectedLocationIds: ["androidSDK"])
        let executor = DeletionExecutor(policyGenerationAuthority: authority)

        let result = await executor.execute(plan)

        #expect(result.items.first?.status.notAttemptedReason == NotAttemptedReason.policyChanged.copy)
        #expect(FileManager.default.fileExists(atPath: child.path(percentEncoded: false)))
    }
}
