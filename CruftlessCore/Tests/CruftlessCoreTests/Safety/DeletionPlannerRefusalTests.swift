import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionPlanner Refusal Tests")
struct DeletionPlannerRefusalTests {
    private func makeTempRoot(named name: String) throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func location(id: String, tier: Tier, roots: [URL]) -> TrackedLocation {
        TrackedLocation(
            id: id,
            title: id,
            icon: .symbol("folder"),
            tier: tier,
            hasDrillDown: false,
            stalenessSource: .topLevelMtime,
            resolveRoots: { roots }
        )
    }

    @Test("The simulator devices location is never planned as a path delete")
    func simulatorDevicesLocationRefused() {
        let entry = InventoryEntry.sized(
            location: LocationCatalog.simulatorDevices,
            reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: LocationCatalog.simulatorDevices.resolveRoots().map { RootSize(url: $0, allocatedBytes: 1) }
        )
        #expect(throws: DeletionPlanningError.simulatorLocation(title: LocationCatalog.simulatorDevices.title)) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }

        let runtimes = InventoryEntry.sized(
            location: LocationCatalog.simulatorRuntimes,
            reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: []
        )
        #expect(throws: DeletionPlanningError.simulatorLocation(title: LocationCatalog.simulatorRuntimes.title)) {
            try DeletionPlanner.wholeLocation(runtimes, context: PlanningContext())
        }
    }

    @Test("A child of a simctl-only location is refused even with a valid path")
    func simctlLocationChildRefused() throws {
        let root = try makeTempRoot(named: "Devices")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let device = root.appendingPathComponent("00000000-0000-0000-0000-000000000001", isDirectory: true)
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)

        let loc = TrackedLocation(
            id: "sims", title: "Simulator devices", icon: .symbol("iphone"), tier: .judgment,
            hasDrillDown: true, stalenessSource: .simulatorPlist, mutationPolicy: .simctl,
            resolveRoots: { [root] }
        )
        let child = ChildEntry(
            id: "dev", name: "iPhone", url: device, reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .judgment, consequence: "none"
        )
        #expect(throws: DeletionPlanningError.simulatorLocation(title: "Simulator devices")) {
            try DeletionPlanner.child(child, in: loc, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.simulatorLocation(title: "Simulator devices")) {
            try DeletionPlanner.children([child], in: loc, context: PlanningContext())
        }
    }

    @Test("A batch with one refused child is refused as a whole, with the reason")
    func partialRefusalFailsBatch() throws {
        let root = try makeTempRoot(named: "DerivedData")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        let fine = root.appendingPathComponent("Fine", isDirectory: true)
        let kept = root.appendingPathComponent("Kept", isDirectory: true)
        try FileManager.default.createDirectory(at: fine, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: kept, withIntermediateDirectories: true)

        let loc = location(id: "derivedData", tier: .regen, roots: [root])
        let children = [fine, kept].map { url in
            ChildEntry(
                id: url.lastPathComponent, name: url.lastPathComponent, url: url, reclaimableBytes: 1,
                staleness: StalenessInfo(lastUsedDate: Date()), tier: .regen, consequence: "regen"
            )
        }
        let policy = ProtectedPaths(customProtectedPaths: [kept])

        #expect(throws: DeletionPlanningError.refused(name: "Kept", error: .protectedPath(ProtectedPaths.normalize(kept)))) {
            try DeletionPlanner.children(children, in: loc, context: PlanningContext(protectedPaths: policy))
        }
    }

    @Test("A child that vanished since the scan is refused with a rescan hint")
    func missingChildRefused() throws {
        let root = try makeTempRoot(named: "DerivedData")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        let gone = root.appendingPathComponent("Gone", isDirectory: true)
        let loc = location(id: "derivedData", tier: .regen, roots: [root])
        let child = ChildEntry(
            id: "gone", name: "Gone", url: gone, reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .regen, consequence: "regen"
        )
        #expect(throws: DeletionPlanningError.missingOnDisk(name: "Gone")) {
            try DeletionPlanner.child(child, in: loc, context: PlanningContext())
        }
    }

    @Test("Every planning error has user-facing copy")
    func everyErrorHasDescription() {
        let errors: [DeletionPlanningError] = [
            .notDeletable(title: "X"),
            .unavailable(title: "X", reason: "r"),
            .flaggedLocation(title: "X"),
            .simulatorLocation(title: "X"),
            .refused(name: "X", error: .outsideAllowlistedRoots("/x")),
            .refused(name: "X", error: .containsProtectedDescendant("/x")),
            .missingOnDisk(name: "X"),
            .nothingToPlan(title: "X")
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty, "\(error)")
        }
    }
}
