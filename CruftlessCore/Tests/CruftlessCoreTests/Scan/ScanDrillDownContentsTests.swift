import CruftlessCore
import Foundation
import Testing

@Suite("Scan produces drill-down contents")
struct ScanDrillDownContentsTests {
    private func makeTree(children: [String]) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for name in children {
            let dir = root.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data(repeating: 0x41, count: 4096).write(to: dir.appendingPathComponent("payload.bin"))
        }
        return root
    }

    private func location(
        id: String,
        roots: [URL],
        hasDrillDown: Bool = true,
        sizeSource: SizeSource = .filesystemRoots
    ) -> TrackedLocation {
        TrackedLocation(
            id: id,
            title: id,
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: hasDrillDown,
            stalenessSource: .topLevelMtime,
            sizeSource: sizeSource,
            resolveRoots: { roots }
        )
    }

    private func collect(_ stream: AsyncStream<ScanEvent>) async -> [ScanEvent] {
        var events: [ScanEvent] = []
        for await event in stream { events.append(event) }
        return events
    }

    private static let runtime = SimRuntime(
        identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
        name: "iOS 18.6",
        build: "22G86",
        sizeBytes: 7_800_000_000,
        isDeletable: true
    )

    @Test("A drill-down location's children land beside its row")
    func childrenLandWithTheRow() async throws {
        let root = try makeTree(children: ["Alpha", "Beta"])
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let derived = location(id: "derivedData", roots: [root])
        let engine = ScanEngine()
        let events = await collect(await engine.scan(catalog: [derived]))

        let contents = events.compactMap { event -> DrillDownContent? in
            if case let .locationContents(_, contents) = event { return contents }
            return nil
        }
        let names: [String] = try {
            let first = try #require(contents.first)
            guard case let .children(children) = first else { return [] }
            return children.map(\.name).sorted()
        }()

        #expect(contents.count == 1)
        #expect(names == ["Alpha", "Beta"])
    }

    @Test("Contents follow the row, never precede it")
    func contentsFollowTheRow() async throws {
        let root = try makeTree(children: ["Alpha"])
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let derived = location(id: "derivedData", roots: [root])
        let engine = ScanEngine()
        let events = await collect(await engine.scan(catalog: [derived]))

        let rowIndex = try #require(events.firstIndex {
            if case .locationScanned = $0 { return true }
            return false
        })
        let contentsIndex = try #require(events.firstIndex {
            if case .locationContents = $0 { return true }
            return false
        })

        #expect(rowIndex < contentsIndex)
    }

    @Test("A location without a drill-down produces no contents")
    func noDrillDownNoContents() async throws {
        let root = try makeTree(children: ["Alpha"])
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let flat = location(id: "previewsCache", roots: [root], hasDrillDown: false)
        let engine = ScanEngine()
        let events = await collect(await engine.scan(catalog: [flat]))

        #expect(!events.contains {
            if case .locationContents = $0 { return true }
            return false
        })
    }

    @Test("The runtimes row carries the list it was sized from")
    func runtimesContentsCarryTheList() async throws {
        let runtimes = location(id: "simulatorRuntimes", roots: [], sizeSource: .simulatorRuntimes)
        let engine = ScanEngine(runtimeLister: { [Self.runtime] })
        let events = await collect(await engine.scan(catalog: [runtimes]))

        let contents = try #require(events.compactMap { event -> DrillDownContent? in
            if case let .locationContents(_, contents) = event { return contents }
            return nil
        }.first)

        guard case let .runtimes(listed) = contents else {
            Issue.record("expected .runtimes, got \(contents)")
            return
        }
        #expect(listed.map(\.name) == ["iOS 18.6"])
    }

    @Test("A failed runtime lookup is unavailable, never an empty list")
    func failedLookupIsUnavailable() async throws {
        struct Boom: Error, LocalizedError {
            var errorDescription: String? { "simctl said no" }
        }

        let runtimes = location(id: "simulatorRuntimes", roots: [], sizeSource: .simulatorRuntimes)
        let engine = ScanEngine(runtimeLister: { throw Boom() })
        let events = await collect(await engine.scan(catalog: [runtimes]))

        let contents = try #require(events.compactMap { event -> DrillDownContent? in
            if case let .locationContents(_, contents) = event { return contents }
            return nil
        }.first)

        #expect(contents.isUnavailable)
        guard case let .unavailable(reason) = contents else { return }
        #expect(reason == "simctl said no")
    }

    @Test("One runtime lookup per scan, shared by both simulator locations")
    func oneRuntimeLookupPerScan() async throws {
        let root = try makeTree(children: ["ABCD-1234"])
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        final class Counter: @unchecked Sendable {
            private let lock = NSLock()
            private(set) var calls = 0
            func record() {
                lock.lock()
                defer { lock.unlock() }
                calls += 1
            }
        }
        let counter = Counter()

        let runtimes = location(id: "simulatorRuntimes", roots: [], sizeSource: .simulatorRuntimes)
        let devices = location(id: "simulatorDevices", roots: [root])
        let engine = ScanEngine(
            runtimeLister: {
                counter.record()
                return [Self.runtime]
            },
            deviceLister: { _ in [] }
        )
        _ = await collect(await engine.scan(catalog: [runtimes, devices]))

        #expect(counter.calls == 1)
    }

    @Test("The devices drill-down carries the scan's per-device sizes")
    func devicesCarrySizes() async throws {
        let udid = "11111111-2222-3333-4444-555555555555"
        let root = try makeTree(children: [udid])
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let device = SimDevice(
            udid: udid,
            name: "iPhone 17 Pro",
            runtime: Self.runtime.runtimeIdentifier,
            state: .shutdown,
            lastUsedAt: nil,
            deviceDirectory: root.appendingPathComponent(udid, isDirectory: true)
        )

        let devices = location(id: "simulatorDevices", roots: [root])
        let engine = ScanEngine(
            runtimeLister: { [Self.runtime] },
            deviceLister: { _ in [device] }
        )
        let events = await collect(await engine.scan(catalog: [devices]))

        let contents = try #require(events.compactMap { event -> DrillDownContent? in
            if case let .locationContents(_, contents) = event { return contents }
            return nil
        }.first)

        guard case let .devices(listed, sizes) = contents else {
            Issue.record("expected .devices, got \(contents)")
            return
        }
        #expect(listed.map(\.udid) == [udid])
        #expect((sizes[udid] ?? 0) > 0)
    }

    @Test("A failed runtime lookup makes the devices drill-down unavailable too")
    func devicesUnavailableWhenRuntimesFail() async throws {
        struct Boom: Error {}
        let root = try makeTree(children: ["ABCD-1234"])
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let devices = location(id: "simulatorDevices", roots: [root])
        let engine = ScanEngine(
            runtimeLister: { throw Boom() },
            deviceLister: { _ in
                Issue.record("the device lister must not run against an unestablished runtime list")
                return []
            }
        )
        let events = await collect(await engine.scan(catalog: [devices]))

        let contents = try #require(events.compactMap { event -> DrillDownContent? in
            if case let .locationContents(_, contents) = event { return contents }
            return nil
        }.first)

        #expect(contents.isUnavailable)
    }
}
