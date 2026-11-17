@testable import CruftlessCore
import Foundation
import Testing

/// With an empty ledger, nothing reached through Xcode settings or Spotlight opens or lists a protected path.
@Suite("Access gate: Xcode installs and custom locations")
struct AccessGateXcodeSourceTests {
    static func events(_ stream: AsyncStream<ScanEvent>) async -> [ScanEvent] {
        var collected: [ScanEvent] = []
        for await event in stream {
            collected.append(event)
        }
        return collected
    }

    static func entry(_ events: [ScanEvent], id: String) -> InventoryEntry? {
        events.compactMap { event -> InventoryEntry? in
            if case let .locationScanned(entry) = event, entry.id == id { return entry }
            return nil
        }.last
    }

    private func makeApp(_ fixture: AccessFixture, _ relative: String) throws -> URL {
        try fixture.file("\(relative)/Contents/Info.plist", bytes: 512)
        try fixture.file("\(relative)/Contents/Developer/payload.bin", bytes: 16384)
        return fixture.home.appendingPathComponent(relative, isDirectory: true)
    }

    @Test("Xcode installs measure the clear copies, count the blocked one, and never open it")
    func xcodeInstalls() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let clearApp = try makeApp(fixture, "Applications/Xcode.app")
        let blockedApp = try makeApp(fixture, "Downloads/Xcode-beta.app")
        let location = TrackedLocation(
            id: "xcodeInstallsFixture",
            title: "Xcode installs",
            icon: .image("xcode"),
            tier: .reveal,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [clearApp, blockedApp] }
        )
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }
        let engine = ScanEngine(accessGate: fixture.gate)

        let events = await Self.events(await engine.scan(catalog: [location]))
        let children = await engine.children(of: location.id, catalog: [location])

        let entry = try #require(Self.entry(events, id: location.id))
        let need = try #require(entry.accessNeed)
        #expect(entry.isUnavailable == false)
        #expect(entry.reclaimableBytes > 0)
        #expect(entry.rootURLs == [clearApp])
        #expect(need.notMeasuredCount == 1)
        #expect(need.isPartial)
        #expect(need.blocked.first?.reason == "Xcode-beta.app")
        #expect(need.blocked.first?.area == .downloads)
        let notice = events.contains { event in
            if case let .failed(id, reason) = event { return id == location.id && reason.contains("Xcode-beta.app") }
            return false
        }
        #expect(notice)
        #expect(children.map(\.name) == ["Xcode.app"])

        #expect(recorder.events(under: fixture.home.appendingPathComponent("Downloads")).isEmpty)
        #expect(!recorder.events(under: clearApp).isEmpty)
    }

    @Test("The simulator toolchain check neither reads nor runs a blocked Xcode")
    func toolchainProbe() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let blockedApp = try makeApp(fixture, "Downloads/Xcode-beta.app")
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }

        let probe = await SimulatorToolchainResolver.probe(candidate: blockedApp, gate: fixture.gate)
        let resolver = SimulatorToolchainResolver(
            candidates: { [blockedApp] },
            selectedDirectory: { nil },
            accessGate: fixture.gate
        )
        let resolution = await resolver.resolve()

        #expect(probe == .blocked(.downloads))
        #expect(resolution == .unavailable(.needsAccess([.downloads])))
        #expect(recorder.events(under: fixture.home.appendingPathComponent("Downloads")).isEmpty)

        // A clear copy with an unparseable Info.plist is read, rejected, and never handed to `xcrun`.
        let clearApp = try makeApp(fixture, "Applications/Xcode.app")
        #expect(await SimulatorToolchainResolver.probe(candidate: clearApp, gate: fixture.gate) == .unusable)
        #expect(recorder.events(under: clearApp).contains { $0.kind == .open })
    }

    private func customDerivedData(_ fixture: AccessFixture) throws -> (TrackedLocation, URL) {
        let root = try fixture.directory("Documents/Builds/DerivedData")
        try fixture.file("Documents/Builds/DerivedData/App-abcdefghijklmnopqrstuvwxyzab/payload.bin", bytes: 8192)
        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["WorkspacePath": fixture.home.appendingPathComponent("Documents/App/App.xcodeproj").path],
            format: .xml,
            options: 0
        )
        try plist.write(to: root.appendingPathComponent("App-abcdefghijklmnopqrstuvwxyzab/info.plist"))
        let defaultRoot = fixture.home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
        let location = TrackedLocation(
            id: LocationCatalog.derivedData.id,
            title: "Derived Data",
            icon: .symbol("hammer"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .newestChildMtime,
            resolveRoots: { [root] },
            resolveDefaultRoots: { [defaultRoot] }
        )
        return (location, root)
    }

    @Test("A custom Derived Data location in Documents is reported as needing access and never opened")
    func customDerivedDataBlocked() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let (location, _) = try customDerivedData(fixture)
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }
        let engine = ScanEngine(accessGate: fixture.gate)

        let scanned = await Self.events(await engine.scan(catalog: [location]))
        let rescanned = await Self.events(await engine.rescan(locationIds: [location.id], catalog: [location]))
        let cold = await engine.children(of: location.id, catalog: [location])
        let planningChildren = DrillDownProvider.loadChildren(for: location, accessGate: fixture.gate)

        for events in [scanned, rescanned] {
            let entry = try #require(Self.entry(events, id: location.id))
            guard case let .needsAccess(_, need) = entry else {
                Issue.record("Expected a needs-access row, got \(entry)")
                continue
            }
            #expect(need.blocked.map(\.reason) == ["Derived Data location"])
            #expect(need.blocked.map(\.state) == [.notAsked])
            #expect(need.isPartial == false)
        }
        let planned = scanned.contains { event in
            if case let .planned(locations) = event { return locations.map(\.id) == [location.id] }
            return false
        }
        #expect(planned)
        #expect(cold.isEmpty)
        #expect(planningChildren.isEmpty)
        #expect(recorder.events(under: fixture.home.appendingPathComponent("Documents")).isEmpty)
    }

    @Test("Once Documents has been asked, the same location is walked")
    func customDerivedDataAfterAsk() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let (location, root) = try customDerivedData(fixture)
        fixture.ledger.markAsked(.documents)
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }

        let events = await Self.events(await ScanEngine(accessGate: fixture.gate).scan(catalog: [location]))

        let entry = try #require(Self.entry(events, id: location.id))
        #expect(entry.accessNeed == nil)
        #expect(entry.reclaimableBytes > 0)
        #expect(!recorder.events(under: root).isEmpty)
    }

    @Test("An asked area whose root cannot be opened reads as not allowed, not as not asked")
    func askedButRefused() async throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let (location, root) = try customDerivedData(fixture)
        fixture.ledger.markAsked(.documents)
        chmod(root.path(percentEncoded: false), 0o000)
        defer { chmod(root.path(percentEncoded: false), 0o755) }

        let events = await Self.events(await ScanEngine(accessGate: fixture.gate).scan(catalog: [location]))

        let entry = try #require(Self.entry(events, id: location.id))
        let need = try #require(entry.accessNeed)
        #expect(entry.isUnavailable)
        #expect(need.isNotAllowed)
        #expect(need.blocked.map(\.state) == [.notAllowed])
    }
}
