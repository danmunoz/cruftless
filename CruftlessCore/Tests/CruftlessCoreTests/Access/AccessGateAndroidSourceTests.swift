@testable import CruftlessCore
import Foundation
import Testing

/// With an empty ledger, Android roots configured into a protected area are neither listed, read nor walked.
@Suite("Access gate: Android roots")
struct AccessGateAndroidSourceTests {
    private func androidLocation(
        id: String,
        discoveryIssue: @escaping @Sendable () -> String? = { nil },
        resolveRoots: @escaping @Sendable () -> [URL]
    ) -> TrackedLocation {
        TrackedLocation(
            id: id,
            platform: .android,
            title: id,
            icon: .symbol("folder"),
            tier: .info,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            mutationPolicy: .readOnly,
            discoveryIssue: discoveryIssue,
            resolveRoots: resolveRoots
        )
    }

    @Test("An AVD home in Documents: no registry listing, no .ini read, no walk")
    func avdHomeInDocuments() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let avdHome = try fixture.directory("Documents/avd")
        let device = try fixture.directory("Documents/avd/Pixel.avd")
        try "path=\(device.path(percentEncoded: false))\navd.ini.displayname=Pixel\n"
            .write(to: avdHome.appendingPathComponent("Pixel.ini"), atomically: true, encoding: .utf8)
        try "hw.device.name=pixel\n".write(to: device.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
        let home = fixture.home
        let gate = fixture.gate
        let environment = ["ANDROID_AVD_HOME": avdHome.path(percentEncoded: false)]
        let location = androidLocation(
            id: "androidAVDs",
            discoveryIssue: { RootResolver.androidAVDIssue(home: home, environment: environment, gate: gate) },
            resolveRoots: { RootResolver.androidAVDRoots(home: home, environment: environment, gate: gate) }
        )
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }
        let engine = ScanEngine(accessGate: gate)

        let roots = RootResolver.androidAVDRoots(home: home, environment: environment, gate: gate)
        let issue = RootResolver.androidAVDIssue(home: home, environment: environment, gate: gate)
        let unresolved = RootResolver.hasUnresolvedAndroidRedirectMetadata(home: home, environment: environment, gate: gate)
        let inventory = RootResolver.androidAVDInventory(roots: [avdHome], gate: gate)
        let events = await AccessGateXcodeSourceTests.events(await engine.scan(catalog: [location]))
        let drillDown = await engine.androidDrillDown(for: location)

        #expect(roots.map(ProtectedPaths.normalize) == [ProtectedPaths.normalize(avdHome)])
        #expect(issue == nil)
        #expect(unresolved, "A blocked registry keeps the home protected from deletion")
        #expect(inventory.isEmpty)
        let entry = try #require(AccessGateXcodeSourceTests.entry(events, id: location.id))
        #expect(entry.accessNeed?.areas == [.documents])
        #expect(entry.isUnavailable)
        #expect(drillDown == nil)
        #expect(recorder.events(under: fixture.home.appendingPathComponent("Documents")).isEmpty)

        fixture.ledger.markAsked(.documents)
        _ = RootResolver.androidAVDRoots(home: home, environment: environment, gate: gate)
        #expect(recorder.events(under: avdHome).contains { $0.kind == .list }, "The seam sees the listing once the area is asked")
    }

    @Test("A readable registry whose device redirects into Documents measures the registry and never opens the device")
    func avdRedirectIntoDocuments() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let registry = try fixture.directory(".android/avd")
        try fixture.file(".android/avd/payload.bin")
        let device = try fixture.directory("Documents/avds/Pixel.avd")
        try fixture.file("Documents/avds/Pixel.avd/userdata.img")
        try "hw.device.name=pixel\n".write(to: device.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)
        try "path=\(device.path(percentEncoded: false))\n"
            .write(to: registry.appendingPathComponent("Pixel.ini"), atomically: true, encoding: .utf8)
        let home = fixture.home
        let gate = fixture.gate
        let location = androidLocation(
            id: "androidAVDs",
            discoveryIssue: { RootResolver.androidAVDIssue(home: home, environment: [:], gate: gate) },
            resolveRoots: { RootResolver.androidAVDRoots(home: home, environment: [:], gate: gate) }
        )
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }
        let engine = ScanEngine(accessGate: gate)

        let events = await AccessGateXcodeSourceTests.events(await engine.scan(catalog: [location]))
        let children = await engine.children(of: location.id, catalog: [location])

        #expect(location.resolveRoots().count == 2)
        let entry = try #require(AccessGateXcodeSourceTests.entry(events, id: location.id))
        #expect(entry.isUnavailable == false)
        #expect(entry.accessNeed?.isPartial == true)
        #expect(entry.accessNeed?.areas == [.documents])
        #expect(!children.contains { $0.url.path(percentEncoded: false).contains("/Documents/") })
        #expect(recorder.events(under: fixture.home.appendingPathComponent("Documents")).isEmpty)
        #expect(!recorder.events(under: registry).isEmpty)
    }

    @Test("SDK and Gradle homes in Documents are reported as needing access and never walked")
    func sdkAndGradleInDocuments() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        try fixture.file("Documents/sdk/platforms/android-35/source.properties", bytes: 64)
        try fixture.file("Documents/gradle/caches/modules-2/payload.bin")
        let home = fixture.home
        let environment = [
            "ANDROID_HOME": home.appendingPathComponent("Documents/sdk").path(percentEncoded: false),
            "GRADLE_USER_HOME": home.appendingPathComponent("Documents/gradle").path(percentEncoded: false)
        ]
        let sdk = androidLocation(id: "androidSDK") { RootResolver.androidSDKRoots(home: home, environment: environment) }
        let gradle = androidLocation(id: "gradleCaches") { RootResolver.gradleCacheRoots(home: home, environment: environment) }
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }
        let engine = ScanEngine(accessGate: fixture.gate)

        let events = await AccessGateXcodeSourceTests.events(await engine.scan(catalog: [sdk, gradle]))
        let sdkDrillDown = await engine.androidDrillDown(for: sdk)
        let sdkChildren = await engine.children(of: sdk.id, catalog: [sdk])

        #expect(sdk.resolveRoots().count == 1)
        #expect(gradle.resolveRoots().count == 1)
        for id in [sdk.id, gradle.id] {
            let entry = try #require(AccessGateXcodeSourceTests.entry(events, id: id))
            #expect(entry.accessNeed?.areas == [.documents])
        }
        #expect(sdkDrillDown == nil)
        #expect(sdkChildren.isEmpty)
        #expect(recorder.events(under: fixture.home.appendingPathComponent("Documents")).isEmpty)
    }
}
