import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionPlanner Safety Tests")
struct DeletionPlannerTests {
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

    @Test("Clearing a whole location produces a plan covering its roots")
    func wholeLocationProducesPlan() throws {
        let root = try makeTempRoot(named: "Previews")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        try "cache".write(to: root.appendingPathComponent("blob"), atomically: true, encoding: .utf8)

        let entry = InventoryEntry.sized(
            location: location(id: "previews", tier: .regen, roots: [root]),
            reclaimableBytes: 4096,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: [RootSize(url: root, allocatedBytes: 4096)]
        )

        let plan = try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        #expect(plan.count == 1)
        #expect(plan.totalReclaimableBytes == 4096)
    }

    @Test("A multi-root location reports each root's own size, not the total")
    func multiRootSizesAreNotDuplicated() throws {
        let products = try makeTempRoot(named: "Products")
        let logs = try makeTempRoot(named: "Logs")
        defer {
            TestFileSystem.removeDirectoryRecursively(at: products.deletingLastPathComponent())
            TestFileSystem.removeDirectoryRecursively(at: logs.deletingLastPathComponent())
        }

        let entry = InventoryEntry.sized(
            location: location(id: "products", tier: .regen, roots: [products, logs]),
            reclaimableBytes: 3000,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: [
                RootSize(url: products, allocatedBytes: 2000),
                RootSize(url: logs, allocatedBytes: 1000)
            ]
        )

        let plan = try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        #expect(plan.count == 2)
        #expect(plan.totalReclaimableBytes == 3000)
    }

    @Test("A flagged location is never planned as a whole-location clear")
    func flaggedLocationIsNeverBatched() throws {
        let root = try makeTempRoot(named: "Archives")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        let entry = InventoryEntry.sized(
            location: location(id: "archives", tier: .irreversible, roots: [root]),
            reclaimableBytes: 9999,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: [RootSize(url: root, allocatedBytes: 9999)]
        )

        #expect(throws: DeletionPlanningError.flaggedLocation(title: "archives")) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }
    }

    @Test("The real Archives catalog entry is also refused")
    func catalogArchivesRefused() {
        let entry = InventoryEntry.sized(
            location: LocationCatalog.archives,
            reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: LocationCatalog.archives.resolveRoots().map { RootSize(url: $0, allocatedBytes: 1) }
        )
        #expect(throws: DeletionPlanningError.flaggedLocation(title: LocationCatalog.archives.title)) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }
    }

    @Test("Reveal-only and root-owned locations are never planned")
    func nonDeletableTiersRefused() throws {
        let root = try makeTempRoot(named: "ReadOnly")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        for tier in [Tier.reveal, .info] {
            let entry = InventoryEntry.sized(
                location: location(id: "loc-\(tier.rawValue)", tier: tier, roots: [root]),
                reclaimableBytes: 10,
                staleness: StalenessInfo(lastUsedDate: Date()),
                roots: [RootSize(url: root, allocatedBytes: 10)]
            )
            #expect(throws: DeletionPlanningError.notDeletable(title: "loc-\(tier.rawValue)")) {
                try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
            }
        }
    }

    @Test("A user-protected path inside a location vetoes the whole-location clear")
    func customProtectedDescendantVetoesClear() throws {
        let root = try makeTempRoot(named: "DerivedData")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        let keep = root.appendingPathComponent("KeepMe", isDirectory: true)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)

        let entry = InventoryEntry.sized(
            location: location(id: "derivedData", tier: .regen, roots: [root]),
            reclaimableBytes: 100,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: [RootSize(url: root, allocatedBytes: 100)]
        )

        let policy = ProtectedPaths(customProtectedPaths: [keep])
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext(protectedPaths: policy))
        }
    }

    @Test("An unavailable entry is never planned")
    func unavailableEntryRefused() {
        let entry = InventoryEntry.unavailable(
            location: LocationCatalog.derivedData,
            reason: "Permission denied"
        )
        #expect(throws: DeletionPlanningError.unavailable(title: LocationCatalog.derivedData.title, reason: "Permission denied")) {
            try DeletionPlanner.wholeLocation(entry, context: PlanningContext())
        }
    }

    @Test("A batch of children drops flagged entries and keeps the rest")
    func childBatchDropsFlagged() throws {
        let root = try makeTempRoot(named: "Archives")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        let plain = root.appendingPathComponent("Build.noindex", isDirectory: true)
        let archive = root.appendingPathComponent("MyApp.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: plain, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        let loc = location(id: "archives", tier: .irreversible, roots: [root])
        let children = [
            ChildEntry(
                id: "plain", name: "Build.noindex", url: plain, reclaimableBytes: 10,
                staleness: StalenessInfo(lastUsedDate: Date()), tier: .regen, consequence: "regen"
            ),
            ChildEntry(
                id: "archive", name: "MyApp.xcarchive", url: archive, reclaimableBytes: 20,
                staleness: StalenessInfo(lastUsedDate: Date()), tier: .irreversible, consequence: "dSYMs"
            )
        ]

        let plan = try DeletionPlanner.children(children, in: loc, context: PlanningContext())
        #expect(plan.count == 1)
        #expect(!plan.hasFlaggedItem)
        #expect(plan.totalReclaimableBytes == 10)
    }

    @Test("A single flagged child chosen explicitly is still plannable")
    func singleFlaggedChildAllowed() throws {
        let root = try makeTempRoot(named: "Archives")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }

        let archive = root.appendingPathComponent("MyApp.xcarchive", isDirectory: true)
        try FileManager.default.createDirectory(at: archive, withIntermediateDirectories: true)

        let loc = location(id: "archives", tier: .irreversible, roots: [root])
        let child = ChildEntry(
            id: "archive", name: "MyApp.xcarchive", url: archive, reclaimableBytes: 20,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .irreversible, consequence: "dSYMs"
        )

        let plan = try DeletionPlanner.child(child, in: loc, context: PlanningContext())
        #expect(plan.count == 1)
        #expect(plan.hasFlaggedItem)
    }

    @Test("Each catalog location carries its exact consequence copy")
    func consequenceStringsMatchCatalog() {
        #expect(
            LocationCatalog.derivedData.consequence
                == "Xcode rebuilds indexes and intermediates on the next build. The next build is slower."
        )
        #expect(
            LocationCatalog.deviceSupport.consequence
                == "Xcode re-creates it the next time that device is connected."
        )
        #expect(
            LocationCatalog.swiftPMCache.consequence
                == "Packages are re-downloaded the next time they resolve. Needs a network connection."
        )
        #expect(
            LocationCatalog.productsLogsDocCache.consequence
                == "Build products and documentation caches are re-created on demand. Device logs are not."
        )
        #expect(
            LocationCatalog.archives.consequence ==
                "Deletes the dSYMs and the archived app. Crash reports from these builds can never be symbolicated, "
                + "and the build can't be re-exported."
        )
        #expect(
            LocationCatalog.codingAssistant.consequence
                == "Coding assistant sessions, agent history and MCP server settings are lost."
        )
        #expect(
            LocationCatalog.simulatorDevices.consequence
                == TrackedLocation.defaultConsequence(for: .judgment)
        )
    }

    @Test("A child outside its location's roots is refused")
    func childOutsideRootRefused() throws {
        let root = try makeTempRoot(named: "DerivedData")
        let elsewhere = try makeTempRoot(named: "Elsewhere")
        defer {
            TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent())
            TestFileSystem.removeDirectoryRecursively(at: elsewhere.deletingLastPathComponent())
        }

        let victim = elsewhere.appendingPathComponent("precious.txt")
        try "precious".write(to: victim, atomically: true, encoding: .utf8)

        let loc = location(id: "derivedData", tier: .regen, roots: [root])
        let child = ChildEntry(
            id: "escape", name: "precious.txt", url: victim, reclaimableBytes: 1,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .regen, consequence: "none"
        )

        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.child(child, in: loc, context: PlanningContext())
        }
        #expect(FileManager.default.fileExists(atPath: victim.path))
    }

}

@Suite("DeletionPlanner custom roots")
struct DeletionPlannerCustomRootTests {
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func location(roots: [URL], defaultRoots: [URL]) -> TrackedLocation {
        TrackedLocation(
            id: "derivedData",
            title: "Derived Data",
            icon: .symbol("hammer"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .newestChildMtime,
            resolveRoots: { roots },
            resolveDefaultRoots: { defaultRoots }
        )
    }

    private func entry(for location: TrackedLocation, root: URL) -> InventoryEntry {
        .sized(
            location: location,
            reclaimableBytes: 100,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: [RootSize(url: root, allocatedBytes: 100)]
        )
    }

    @Test("A custom root plans its children by name, never the folder itself")
    func customRootPlansChildren() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let custom = base.appendingPathComponent("Repos", isDirectory: true)
        let projectA = custom.appendingPathComponent("MyApp-abcdefghijklmnopqrstuvwxyz12", isDirectory: true)
        let projectB = custom.appendingPathComponent("Thesis", isDirectory: true)
        for dir in [projectA, projectB] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try "x".write(to: dir.appendingPathComponent("file"), atomically: true, encoding: .utf8)
        }

        let defaultRoot = base.appendingPathComponent("DerivedData", isDirectory: true)
        let location = location(roots: [custom], defaultRoots: [defaultRoot])
        #expect(location.isCustomRoot(custom))
        #expect(!location.isCustomRoot(defaultRoot))

        let plan = try DeletionPlanner.wholeLocation(entry(for: location, root: custom), context: PlanningContext())

        let paths = Set(plan.items.compactMap { $0.validatedPath?.path })
        #expect(paths == Set([projectA, projectB].map(ProtectedPaths.normalize)))
        #expect(!paths.contains(ProtectedPaths.normalize(custom)))
        #expect(Set(plan.items.map(\.name)) == ["Derived Data · MyApp-abcdefghijklmnopqrstuvwxyz12", "Derived Data · Thesis"])
    }

    @Test("A custom root with nothing inside refuses rather than deleting the folder")
    func emptyCustomRootRefuses() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let custom = base.appendingPathComponent("Empty", isDirectory: true)
        try FileManager.default.createDirectory(at: custom, withIntermediateDirectories: true)
        let location = location(roots: [custom], defaultRoots: [base.appendingPathComponent("DerivedData")])

        #expect(throws: DeletionPlanningError.nothingToPlan(title: "Derived Data")) {
            try DeletionPlanner.wholeLocation(entry(for: location, root: custom), context: PlanningContext())
        }
    }

    @Test("The default root is still cleared as one row")
    func defaultRootPlansItself() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let defaultRoot = base.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: defaultRoot.appendingPathComponent("P"), withIntermediateDirectories: true)
        let location = location(roots: [defaultRoot], defaultRoots: [defaultRoot])

        let plan = try DeletionPlanner.wholeLocation(entry(for: location, root: defaultRoot), context: PlanningContext())
        #expect(plan.count == 1)
        #expect(plan.items.first?.validatedPath?.path == ProtectedPaths.normalize(defaultRoot))
        #expect(plan.items.first?.name == "Derived Data")
    }

    @Test("The caller's child listing is used, so nothing is walked at plan time")
    func callerSuppliesChildren() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let custom = base.appendingPathComponent("Custom", isDirectory: true)
        let child = custom.appendingPathComponent("Only", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        let location = location(roots: [custom], defaultRoots: [base.appendingPathComponent("DerivedData")])
        let supplied = ChildEntry(
            id: "supplied", name: "Only", url: child, reclaimableBytes: 42,
            staleness: StalenessInfo(lastUsedDate: nil), tier: .regen, consequence: "c"
        )

        let plan = try DeletionPlanner.wholeLocation(
            entry(for: location, root: custom),
            context: PlanningContext().withChildren { _ in [supplied] }
        )
        #expect(plan.count == 1)
        #expect(plan.totalReclaimableBytes == 42)
    }
}
