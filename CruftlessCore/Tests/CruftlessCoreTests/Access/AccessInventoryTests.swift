@testable import CruftlessCore
import Darwin
import Foundation
import Testing

@Suite("Access state in planning, snapshots and the orphan check")
struct AccessInventoryTests {
    private static let need = LocationAccessNeed(
        blocked: [BlockedAccess(
            path: "/Users/someone/Documents/DerivedData",
            area: .documents,
            state: .notAsked,
            reason: "Derived Data location"
        )],
        measuredRootCount: 0
    )

    private static let capacity = VolumeCapacity(totalBytes: 100, freeBytes: 50, purgeableBytes: 0, usedBytes: 50)

    @Test("Planning a whole-location clear on a blocked row is refused with copy naming the area")
    func plannerRefusesBlockedLocation() {
        let entry = InventoryEntry.needsAccess(location: LocationCatalog.derivedData, need: Self.need)

        #expect(throws: DeletionPlanningError.needsAccess(title: "Derived Data", need: Self.need)) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }
        let copy = DeletionPlanningError.needsAccess(title: "Derived Data", need: Self.need).errorDescription
        #expect(copy?.contains("Documents") == true)
        #expect(copy?.contains("Nothing there has been read") == true)
    }

    @Test("A row that measured some roots and skipped others is refused whole")
    func plannerRefusesPartialLocation() {
        let partial = LocationAccessNeed(blocked: Self.need.blocked, measuredRootCount: 1)
        let entry = InventoryEntry.sized(
            location: LocationCatalog.deviceSupport,
            reclaimableBytes: 4096,
            staleness: StalenessInfo(lastUsedDate: nil),
            roots: [RootSize(url: URL(fileURLWithPath: "/tmp/device-support"), allocatedBytes: 4096)],
            accessNeed: partial
        )

        #expect(throws: DeletionPlanningError.needsAccess(title: "Device Support", need: partial)) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }
    }

    @Test("Blocked and partly measured rows survive a snapshot round trip")
    func snapshotRoundTrip() throws {
        let partial = LocationAccessNeed(blocked: Self.need.blocked, measuredRootCount: 1)
        let inventory = Inventory(
            entries: [
                .needsAccess(location: LocationCatalog.derivedData, need: Self.need),
                .sized(
                    location: LocationCatalog.xcodeInstalls,
                    reclaimableBytes: 2048,
                    staleness: StalenessInfo(lastUsedDate: nil),
                    roots: [RootSize(url: URL(fileURLWithPath: "/Applications/Xcode.app"), allocatedBytes: 2048)],
                    accessNeed: partial
                )
            ],
            capacity: Self.capacity,
            scannedAt: Date(timeIntervalSince1970: 0),
            sizesAreUpperBound: true
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let data = try encoder.encode(InventorySnapshot(inventory))
        let restored = try #require(try decoder.decode(InventorySnapshot.self, from: data).inventory(capacity: Self.capacity))

        #expect(restored.entries.first { $0.id == "derivedData" } == .needsAccess(location: LocationCatalog.derivedData, need: Self.need))
        #expect(restored.entries.first { $0.id == "xcodeInstalls" }?.accessNeed == partial)
    }

    @Test("A version four snapshot, written before access state existed, still decodes")
    func readsVersionFour() throws {
        let json = """
        {
          "version": 4,
          "scannedAt": "2026-01-01T00:00:00Z",
          "sizesAreUpperBound": true,
          "optInReclaimableBytes": 0,
          "rows": [
            {"locationId": "derivedData", "kind": {"sized": {"bytes": 4096, "eligibleCleanupBytes": 4096}},
             "lastUsedDate": null, "roots": [{"path": "/tmp/derived", "allocatedBytes": 4096}]},
            {"locationId": "toolchains", "kind": {"unavailable": {"reason": "permission denied"}},
             "lastUsedDate": null, "roots": []}
          ]
        }
        """
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        let restored = try #require(try decoder.decode(InventorySnapshot.self, from: Data(json.utf8)).inventory(capacity: Self.capacity))

        #expect(restored.entries.count == 2)
        #expect(restored.entries.allSatisfy { $0.accessNeed == nil })
        #expect(restored.entries.first?.reclaimableBytes == 4096)
    }

    @Test("The orphan check reads only metadata of the recorded project, even inside a protected area")
    func orphanCheckIsMetadataOnly() throws {
        let fixture = try AccessFixture()
        defer { fixture.remove() }
        let projects = try fixture.directory("Documents/Projects")
        let live = try fixture.directory("Documents/Projects/App.xcodeproj")
        try fixture.file("Documents/Projects/App.xcodeproj/project.pbxproj", bytes: 128)
        let missing = projects.appendingPathComponent("Gone.xcodeproj").path(percentEncoded: false)
        // Unlistable parent and unreadable project: only stat and lstat can still answer.
        chmod(live.path(percentEncoded: false), 0o000)
        chmod(projects.path(percentEncoded: false), 0o111)
        defer {
            chmod(projects.path(percentEncoded: false), 0o755)
            chmod(live.path(percentEncoded: false), 0o755)
        }
        let recorder = FileAccessRecorder()
        defer { recorder.stop() }

        let liveResult = DerivedDataWorkspaceReader.classify(workspacePath: live.path(percentEncoded: false))
        let missingResult = DerivedDataWorkspaceReader.classify(workspacePath: missing)

        #expect(liveResult == .live(live.path(percentEncoded: false)))
        #expect(missingResult == .orphaned(missing))
        #expect(recorder.events(under: projects).isEmpty)
    }
}
