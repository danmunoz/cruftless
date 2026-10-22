import CruftlessCore
import Foundation
import Testing

@Suite("Installed simulator runtime catalog")
struct SimulatorRuntimeCatalogTests {
    @Test("Parses installation membership independently from management UUIDs")
    func parsesFullCatalog() throws {
        let json = #"""
        {"runtimes":[
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-18-6","version":"18.6","buildversion":"22G86","isAvailable":true},
          {"identifier":"com.apple.CoreSimulator.SimRuntime.iOS-27-0","version":"27.0","buildversion":"24A5418b",
           "isAvailable":false,"availabilityError":"missing asset"}
        ]}
        """#
        let catalog = try SimulatorRuntimeCatalog(jsonData: Data(json.utf8))
        #expect(catalog.runtimes.count == 2)
        #expect(catalog.runtimes[0].version == "18.6")
        #expect(catalog.runtimes[1].availabilityError == "missing asset")
    }

    @Test("Availability distinguishes installed unavailable from missing and unknown")
    func deviceAvailability() {
        let device = SimDevice(udid: "01234567-89AB-CDEF-0123-456789ABCDEF", name: "Phone", runtime: "runtime",
                               state: .shutdown, lastUsedAt: nil, deviceDirectory: URL(fileURLWithPath: "/tmp/device"))
        let unavailable = SimulatorRuntimeCatalog(runtimes: [.init(
            identifier: "runtime",
            version: "1",
            build: "A",
            isAvailable: false,
            availabilityError: "asset missing"
        )])
        #expect(UnavailableDetector.reconcile(devices: [device], catalog: unavailable).first?
            .runtimeAvailability == .installedUnavailable("asset missing"))
        #expect(UnavailableDetector.reconcile(devices: [device], catalog: .init(runtimes: [])).first?.runtimeAvailability == .missing)
        #expect(UnavailableDetector.reconcile(devices: [device], catalog: nil, failure: "timed out").first?
            .runtimeAvailability == .unknown("timed out"))
    }

    @Test("Unknown runtime size is not actionable even when the manager reports a delete identifier")
    func unknownSizeCannotBePlanned() {
        let runtime = SimRuntime(identifier: "runtime-id", runtimeIdentifier: "runtime", name: "iOS Runtime",
                                 build: "A", sizeBytes: 0, isDeletable: true, sizeIsKnown: false)
        #expect(!runtime.canPlanDelete)
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.runtimeDelete(runtime, context: PlanningContext())
        }
    }

    @Test("Asset sizing requires a unique exact build and version match")
    func assetSizingUsesMetadata() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let asset = root.appendingPathComponent("fixture.asset", isDirectory: true)
        let dataDirectory = asset.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: dataDirectory, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 2048).write(to: dataDirectory.appendingPathComponent("runtime.dmg"))
        let metadata: [String: Any] = ["MobileAssetProperties": ["Build": "22G86", "SimulatorVersion": "18.6"]]
        let info = try PropertyListSerialization.data(fromPropertyList: metadata, format: .xml, options: 0)
        try info.write(to: asset.appendingPathComponent("Info.plist"))
        #expect((SimulatorRuntimeAssetInventory.sizeBytes(version: "18.6", build: "22G86", root: root) ?? 0) > 0)
        #expect(SimulatorRuntimeAssetInventory.sizeBytes(version: "18.6", build: "wrong", root: root) == nil)
    }

    @Test("Multiple installed builds produce an order-independent unknown device state")
    func ambiguousBuildsRefuseAuthority() {
        let device = SimDevice(udid: UUID().uuidString, name: "Phone", runtime: "runtime", state: .shutdown,
                               lastUsedAt: nil, deviceDirectory: URL(fileURLWithPath: "/tmp/device"))
        let builds: [SimulatorRuntimeCatalog.Runtime] = [
            .init(identifier: "runtime", version: "1", build: "A", isAvailable: true),
            .init(identifier: "runtime", version: "1", build: "B", isAvailable: false)
        ]
        let first = UnavailableDetector.reconcile(devices: [device], catalog: .init(runtimes: builds))[0]
        let reversed = UnavailableDetector.reconcile(devices: [device], catalog: .init(runtimes: builds.reversed()))[0]
        #expect(first.runtimeAvailability == reversed.runtimeAvailability)
        if case .unknown = first.runtimeAvailability {} else { Issue.record("Ambiguous builds must not grant authority") }
    }

    @Test("Full-catalog builds have distinct stable row identities")
    func buildAwareRowIdentity() {
        let first = SimRuntime(
            identifier: "runtime",
            runtimeIdentifier: "runtime",
            name: "OS",
            build: "A",
            sizeBytes: 1,
            isDeletable: false
        )
        let second = SimRuntime(
            identifier: "runtime",
            runtimeIdentifier: "runtime",
            name: "OS",
            build: "B",
            sizeBytes: 1,
            isDeletable: false
        )
        #expect(first.id != second.id)
        let managed = SimRuntime(
            identifier: UUID().uuidString,
            runtimeIdentifier: "runtime",
            name: "OS",
            build: "A",
            sizeBytes: 1,
            isDeletable: true
        )
        #expect(first.id == managed.id)
    }

    @Test("Runtime aliases and hardlinked assets are attributed once")
    func assetStorageDeduplicates() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        func asset(_ name: String, version: String, build: String) throws -> URL {
            let directory = root.appendingPathComponent("\(name).asset", isDirectory: true)
            let data = directory.appendingPathComponent("AssetData", isDirectory: true)
            try FileManager.default.createDirectory(at: data, withIntermediateDirectories: true)
            let metadata: [String: Any] = ["MobileAssetProperties": ["Build": build, "SimulatorVersion": version]]
            try PropertyListSerialization.data(fromPropertyList: metadata, format: .binary, options: 0)
                .write(to: directory.appendingPathComponent("Info.plist"))
            return data.appendingPathComponent("runtime.dmg")
        }
        let firstFile = try asset("first", version: "1", build: "A")
        try Data(repeating: 1, count: 65536).write(to: firstFile)
        let secondFile = try asset("second", version: "2", build: "B")
        try FileManager.default.linkItem(at: firstFile, to: secondFile)
        let runtimes: [SimulatorRuntimeCatalog.Runtime] = [
            .init(identifier: "one", version: "1", build: "A", isAvailable: true),
            .init(identifier: "one-alias", version: "1", build: "A", isAvailable: true),
            .init(identifier: "two", version: "2", build: "B", isAvailable: true)
        ]
        let sizes = SimulatorRuntimeAssetInventory.sizesBytes(for: runtimes, root: root)
        let single = try #require(SimulatorRuntimeAssetInventory.sizeBytes(version: "1", build: "A", root: root))
        #expect(sizes.count == 3)
        #expect(sizes.values.reduce(0, +) == single)
    }

    @Test("Eligible byte accounting stays between zero and stored bytes", arguments: [-10, 0, 50, 200])
    func eligibleBytesClamp(explicit: Int64) {
        let entry = InventoryEntry.sized(location: LocationCatalog.xctestDevices, reclaimableBytes: 100,
                                         staleness: StalenessInfo(lastUsedDate: nil), roots: [], eligibleCleanupBytes: explicit)
        #expect(entry.eligibleCleanupBytes == min(100, max(0, explicit)))
    }
}
