import CruftlessCore
import Foundation
import Testing

@Suite("Top-level rows honour stalenessSource")
struct TopLevelStalenessTests {
    private static let archiveDate = Date(timeIntervalSince1970: 1_700_000_000) // Nov 2023
    private static let deviceDate = Date(timeIntervalSince1970: 1_600_000_000) // Sep 2020

    private static func scanStaleness(_ location: TrackedLocation) async -> StalenessInfo? {
        for await event in await ScanEngine().scan(catalog: [location]) {
            if case let .locationScanned(entry) = event {
                return entry.staleness
            }
        }
        return nil
    }

    // MARK: - Archives

    private static func makeArchiveRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archive = root
            .appendingPathComponent("2023-11-14", isDirectory: true)
            .appendingPathComponent("MyApp.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CreationDate": archiveDate],
            format: .xml,
            options: 0
        )
        try plist.write(to: archive.appendingPathComponent("Info.plist"))
        try Data(repeating: 0x41, count: 4096).write(to: archive.appendingPathComponent("dSYMs.bin"))
        return root
    }

    @Test("Archives takes the newest xcarchive CreationDate, not the newest mtime")
    func archiveCreationDateIsUsed() async throws {
        let root = try Self.makeArchiveRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let location = TrackedLocation(
            id: "archivesStalenessTest",
            title: "Archives",
            icon: .symbol("archivebox"),
            tier: .irreversible,
            hasDrillDown: true,
            stalenessSource: .archiveCreationDate,
            resolveRoots: { [root] }
        )

        let staleness = try #require(await Self.scanStaleness(location))
        let lastUsed = try #require(staleness.lastUsedDate)
        #expect(abs(lastUsed.timeIntervalSince(Self.archiveDate)) < 1.0)
    }

    @Test("The helper also finds an xcarchive sitting directly under the root")
    func archiveDirectlyUnderRoot() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let archive = root.appendingPathComponent("Loose.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let plist = try PropertyListSerialization.data(
            fromPropertyList: ["CreationDate": Self.archiveDate],
            format: .xml,
            options: 0
        )
        try plist.write(to: archive.appendingPathComponent("Info.plist"))

        let newest = try #require(ArchiveDates.newestCreationDate(under: root))
        #expect(abs(newest.timeIntervalSince(Self.archiveDate)) < 1.0)
    }

    @Test("A root holding no archives has no staleness to render")
    func emptyArchivesRootHasNoStaleness() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        try Data(repeating: 0x41, count: 1024).write(to: root.appendingPathComponent("stray.txt"))

        let location = TrackedLocation(
            id: "emptyArchivesTest",
            title: "Archives",
            icon: .symbol("archivebox"),
            tier: .irreversible,
            hasDrillDown: true,
            stalenessSource: .archiveCreationDate,
            resolveRoots: { [root] }
        )

        let staleness = try #require(await Self.scanStaleness(location))
        #expect(staleness.lastUsedDate == nil)
    }

    // MARK: - Simulator devices

    private static func makeDeviceSet() throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)

        let entries: [(Date, String)] = [
            (deviceDate, "iPhone 17 Pro"),
            (deviceDate.addingTimeInterval(-86_400 * 30), "iPad Pro")
        ]

        for (lastUsedAt, name) in entries {
            let udid = UUID().uuidString
            let deviceDir = root.appendingPathComponent(udid, isDirectory: true)
            try FileManager.default.createDirectory(at: deviceDir, withIntermediateDirectories: true)

            let contents: [String: Any] = [
                "UDID": udid,
                "name": name,
                "deviceType": "com.apple.CoreSimulator.SimDeviceType.iPhone-17-Pro",
                "runtime": "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                "state": 1,
                "lastUsedAt": lastUsedAt
            ]
            let plist = try PropertyListSerialization.data(fromPropertyList: contents, format: .xml, options: 0)
            try plist.write(to: deviceDir.appendingPathComponent("device.plist"))
        }

        return root
    }

    @Test("Simulator devices take the newest device.plist lastUsedAt")
    func simulatorPlistDateIsUsed() async throws {
        let root = try Self.makeDeviceSet()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let location = TrackedLocation(
            id: "simulatorStalenessTest",
            title: "Simulator devices",
            icon: .symbol("iphone"),
            tier: .judgment,
            hasDrillDown: true,
            stalenessSource: .simulatorPlist,
            mutationPolicy: .simctl,
            resolveRoots: { [root] }
        )

        let staleness = try #require(await Self.scanStaleness(location))
        let lastUsed = try #require(staleness.lastUsedDate)
        #expect(abs(lastUsed.timeIntervalSince(Self.deviceDate)) < 1.0)
    }

    // MARK: - Mtime sources are unchanged

    @Test("Mtime-based sources still use the recursive newest mtime", arguments: [
        StalenessSource.topLevelMtime, StalenessSource.newestChildMtime
    ])
    func mtimeSourcesUseRecursiveNewest(source: StalenessSource) async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let nested = root.appendingPathComponent("a/b", isDirectory: true)
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        try Data(repeating: 0x41, count: 1024).write(to: nested.appendingPathComponent("deep.bin"))

        let location = TrackedLocation(
            id: "mtimeStalenessTest-\(source)",
            title: "Mtime",
            icon: .symbol("folder"),
            tier: .regen,
            hasDrillDown: false,
            stalenessSource: source,
            resolveRoots: { [root] }
        )

        let staleness = try #require(await Self.scanStaleness(location))
        let lastUsed = try #require(staleness.lastUsedDate)
        #expect(abs(lastUsed.timeIntervalSinceNow) < 120)
    }
}
