import CruftlessCore
import CruftlessFixtures
import Darwin
import Foundation
import Testing

@Suite("DrillDownProvider listing tests")
struct DrillDownProviderTests {
    private func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func location(id: String, tier: Tier = .regen, roots: [URL]) -> TrackedLocation {
        TrackedLocation(
            id: id,
            title: id,
            icon: .symbol("folder"),
            tier: tier,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { roots }
        )
    }

    @discardableResult
    private func makeChild(_ parent: URL, _ name: String, bytes: Int = 4096) throws -> URL {
        let dir = parent.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: dir.appendingPathComponent("payload.bin"))
        return dir
    }

    @Test("A symlink child is not listed")
    func symlinkChildSkipped() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Root", isDirectory: true)
        let outside = base.appendingPathComponent("Outside", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        let real = try makeChild(root, "RealProject")
        try Data(repeating: 0x42, count: 8192).write(to: outside.appendingPathComponent("precious.bin"))

        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("LinkInside"),
            withDestinationURL: real
        )
        try FileManager.default.createSymbolicLink(
            at: root.appendingPathComponent("LinkOutside"),
            withDestinationURL: outside
        )

        let children = DrillDownProvider.loadChildren(for: location(id: "derivedData", roots: [root]))

        #expect(children.map(\.name) == ["RealProject"])
        #expect(FileManager.default.fileExists(atPath: outside.appendingPathComponent("precious.bin").path))
    }

    @Test("A symlinked archive inside a date folder is not listed")
    func symlinkedArchiveSkipped() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Archives", isDirectory: true)
        let dateFolder = root.appendingPathComponent("2026-09-06", isDirectory: true)
        try FileManager.default.createDirectory(at: dateFolder, withIntermediateDirectories: true)
        let real = try makeChild(dateFolder, "MyApp.xcarchive")
        try FileManager.default.createSymbolicLink(
            at: dateFolder.appendingPathComponent("Alias.xcarchive"),
            withDestinationURL: real
        )

        let children = DrillDownProvider.loadChildren(
            for: location(id: "archives", tier: .irreversible, roots: [root])
        )

        #expect(children.map(\.name) == ["MyApp.xcarchive"])
    }

    @Test("Hidden entries are listed")
    func hiddenEntriesListed() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Root", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try makeChild(root, "Visible")
        try makeChild(root, ".hidden-cache")

        let children = DrillDownProvider.loadChildren(for: location(id: "derivedData", roots: [root]))

        #expect(Set(children.map(\.name)) == ["Visible", ".hidden-cache"])
        #expect(children.allSatisfy { $0.reclaimableBytes > 0 })
    }

    @Test("Same-named children in two roots get distinct ids")
    func idsAreUniqueAcrossRoots() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let rootA = base.appendingPathComponent("RootA", isDirectory: true)
        let rootB = base.appendingPathComponent("RootB", isDirectory: true)
        try FileManager.default.createDirectory(at: rootA, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: rootB, withIntermediateDirectories: true)
        try makeChild(rootA, "iOS 27.0")
        try makeChild(rootB, "iOS 27.0")

        let children = DrillDownProvider.loadChildren(for: location(id: "deviceSupport", roots: [rootA, rootB]))

        #expect(children.count == 2)
        #expect(Set(children.map(\.id)).count == 2)
        #expect(Set(children.map(\.url.path)).count == 2)
    }

    @Test("Same-named archives in two date folders get distinct ids")
    func archiveIdsAreUniqueAcrossDateFolders() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Archives", isDirectory: true)
        for day in ["2026-09-05", "2026-09-06"] {
            let folder = root.appendingPathComponent(day, isDirectory: true)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try makeChild(folder, "MyApp.xcarchive")
        }

        let children = DrillDownProvider.loadChildren(
            for: location(id: "archives", tier: .irreversible, roots: [root])
        )

        #expect(children.count == 2)
        #expect(children.allSatisfy { $0.name == "MyApp.xcarchive" })
        #expect(Set(children.map(\.id)).count == 2)
    }

    @Test("A drill-down after a scan still sizes hardlinked content")
    func drillDownAfterScanSizesHardlinks() async throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Archives", isDirectory: true)
        let dateFolder = root.appendingPathComponent("2026-09-06", isDirectory: true)
        try FileManager.default.createDirectory(at: dateFolder, withIntermediateDirectories: true)

        let first = try makeChild(dateFolder, "First.xcarchive", bytes: 200_000)
        #expect(link(
            first.appendingPathComponent("payload.bin").path(percentEncoded: false),
            first.appendingPathComponent("payload-hardlink.bin").path(percentEncoded: false)
        ) == 0)
        try makeChild(dateFolder, "Second.xcarchive", bytes: 100_000)

        let archives = location(id: "archives", tier: .irreversible, roots: [root])
        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: [archives]) {}

        let children = await engine.children(of: "archives", catalog: [archives])
        #expect(children.count == 2)
        for child in children {
            #expect(child.reclaimableBytes > 0, "\(child.name) sized to 0 after the scan")
        }

        let reloaded = await engine.children(of: "archives", catalog: [archives])
        #expect(reloaded.map(\.reclaimableBytes) == children.map(\.reclaimableBytes))
    }

    @Test("An archives drill-down is served from the scan's sizes, not re-walked")
    func archivesDrillDownUsesScanSizes() async throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Archives", isDirectory: true)
        let dateFolder = root.appendingPathComponent("2026-09-06", isDirectory: true)
        try FileManager.default.createDirectory(at: dateFolder, withIntermediateDirectories: true)
        let archive = try makeChild(dateFolder, "MyApp.xcarchive", bytes: 120_000)

        let archives = location(id: "archives", tier: .irreversible, roots: [root])
        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: [archives]) {}

        let measured = try #require(
            await engine.children(of: "archives", catalog: [archives]).first
        ).reclaimableBytes
        #expect(measured > 0)

        TestFileSystem.removeFile(at: archive.appendingPathComponent("payload.bin"))

        let afterEmptying = try #require(
            await engine.children(of: "archives", catalog: [archives]).first
        )
        #expect(afterEmptying.reclaimableBytes == measured)
    }

    @Test("An Xcode install drill-down is served from the scan's sizes")
    func bundleRootUsesScanSizes() async throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let bundle = base.appendingPathComponent("Xcode.app", isDirectory: true)
        let contents = bundle.appendingPathComponent("Contents", isDirectory: true)
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let payload = contents.appendingPathComponent("MacOS.bin")
        try Data(repeating: 0x42, count: 80_000).write(to: payload)

        let installs = location(id: "xcodeInstalls", roots: [bundle])
        let engine = ScanEngine()
        for await _ in await engine.scan(catalog: [installs]) {}

        let measured = try #require(
            await engine.children(of: "xcodeInstalls", catalog: [installs]).first
        ).reclaimableBytes
        #expect(measured > 0)

        TestFileSystem.removeFile(at: payload)

        let afterEmptying = try #require(
            await engine.children(of: "xcodeInstalls", catalog: [installs]).first
        )
        #expect(afterEmptying.name == "Xcode.app")
        #expect(afterEmptying.reclaimableBytes == measured)
    }

    @Test("Archive rows sum to no more than the location total")
    func archiveRowsDoNotExceedTotal() async throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Archives", isDirectory: true)
        let dateFolder = root.appendingPathComponent("2026-09-06", isDirectory: true)
        try FileManager.default.createDirectory(at: dateFolder, withIntermediateDirectories: true)
        try makeChild(dateFolder, "MyApp.xcarchive", bytes: 60_000)
        try Data(repeating: 0x43, count: 8192)
            .write(to: dateFolder.appendingPathComponent(".DS_Store"))
        try FileManager.default.createSymbolicLink(
            at: dateFolder.appendingPathComponent("Latest.xcarchive"),
            withDestinationURL: dateFolder.appendingPathComponent("MyApp.xcarchive")
        )

        let archives = location(id: "archives", tier: .irreversible, roots: [root])
        let engine = ScanEngine()
        var total: Int64 = 0
        for await event in await engine.scan(catalog: [archives]) {
            if case let .locationScanned(entry) = event { total = entry.reclaimableBytes }
        }

        let children = await engine.children(of: "archives", catalog: [archives])
        let summed = children.reduce(Int64(0)) { $0 + $1.reclaimableBytes }

        #expect(children.count == 1, "a symlinked archive is never a row")
        #expect(summed > 0)
        #expect(summed <= total)
    }

    @Test("A simulator device row reads its own device.plist lastUsedAt")
    func simulatorDeviceRowUsesPlistLastUsedAt() throws {
        let base = try makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let devicesRoot = base.appendingPathComponent("Devices", isDirectory: true)
        try FileManager.default.createDirectory(at: devicesRoot, withIntermediateDirectories: true)

        let udid = UUID().uuidString
        let deviceDir = devicesRoot.appendingPathComponent(udid, isDirectory: true)
        try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: deviceDir.appendingPathComponent("payload.bin"))

        let lastUsedAt = Date(timeIntervalSince1970: 1_600_000_000) // Sep 2020
        let plistContents: [String: Any] = [
            "UDID": udid,
            "name": "iPhone 17 Pro",
            "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
            "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            "state": 1,
            "lastUsedAt": lastUsedAt
        ]
        let plistData = try PropertyListSerialization.data(fromPropertyList: plistContents, format: .xml, options: 0)
        try plistData.write(to: deviceDir.appendingPathComponent("device.plist"))

        let simulatorDevices = TrackedLocation(
            id: "simulatorDevicesTest",
            title: "Simulator devices",
            icon: .symbol("iphone"),
            tier: .judgment,
            hasDrillDown: true,
            stalenessSource: .simulatorPlist,
            mutationPolicy: .simctl,
            resolveRoots: { [devicesRoot] }
        )

        let children = DrillDownProvider.loadChildren(for: simulatorDevices)
        let row = try #require(children.first { $0.name == udid })
        let staleDate = try #require(row.staleness.lastUsedDate)
        #expect(abs(staleDate.timeIntervalSince(lastUsedAt)) < 1.0)
    }
}
