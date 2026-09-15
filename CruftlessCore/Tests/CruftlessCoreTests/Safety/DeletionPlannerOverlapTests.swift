import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionPlanner tier and overlap gates")
struct DeletionPlannerOverlapTests {
    private func makeRoot() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .appendingPathComponent("Root", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    private func location(id: String, tier: Tier, roots: [URL]) -> TrackedLocation {
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

    private func child(_ url: URL, name: String? = nil, tier: Tier = .regen, bytes: Int64 = 10) -> ChildEntry {
        ChildEntry(
            id: ProtectedPaths.normalize(url),
            name: name ?? url.lastPathComponent,
            url: url,
            reclaimableBytes: bytes,
            staleness: StalenessInfo(lastUsedDate: Date()),
            tier: tier,
            consequence: "none"
        )
    }

    // MARK: - Tier gates

    @Test("A child of a non-deletable location is refused", arguments: [Tier.reveal, Tier.info])
    func nonDeletableLocationRefused(tier: Tier) throws {
        let root = try makeRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let dir = root.appendingPathComponent("Item", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let loc = location(id: "readOnly", tier: tier, roots: [root])
        let entry = child(dir, tier: tier)

        #expect(throws: DeletionPlanningError.notDeletable(title: "readOnly")) {
            try DeletionPlanner.child(entry, in: loc, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.notDeletable(title: "readOnly")) {
            try DeletionPlanner.children([entry], in: loc, context: PlanningContext())
        }
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("A non-deletable child inside a deletable location is refused")
    func nonDeletableChildRefused() throws {
        let root = try makeRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let deletable = root.appendingPathComponent("Cache", isDirectory: true)
        let readOnly = root.appendingPathComponent("dyld", isDirectory: true)
        try FileManager.default.createDirectory(at: deletable, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: readOnly, withIntermediateDirectories: true)

        let loc = location(id: "simulatorCaches", tier: .regen, roots: [root])

        #expect(throws: DeletionPlanningError.notDeletable(title: "dyld")) {
            try DeletionPlanner.child(child(readOnly, tier: .info), in: loc, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.notDeletable(title: "dyld")) {
            try DeletionPlanner.children(
                [child(deletable), child(readOnly, tier: .info)],
                in: loc,
                context: PlanningContext()
            )
        }
        #expect(FileManager.default.fileExists(atPath: deletable.path))
    }

    // MARK: - Overlapping targets

    @Test("Two children resolving to the same path refuse the batch")
    func duplicateTargetsRefused() throws {
        let root = try makeRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let dir = root.appendingPathComponent("Project", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        let loc = location(id: "derivedData", tier: .regen, roots: [root])
        let first = child(dir, name: "Project")
        let second = ChildEntry(
            id: "duplicate", name: "Project-alias", url: dir, reclaimableBytes: 10,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .regen, consequence: "none"
        )

        #expect(throws: DeletionPlanningError.duplicateTarget(name: "Project-alias")) {
            try DeletionPlanner.children([first, second], in: loc, context: PlanningContext())
        }
        #expect(FileManager.default.fileExists(atPath: dir.path))
    }

    @Test("A child nested inside another child refuses the batch")
    func nestedTargetsRefused() throws {
        let root = try makeRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let outer = root.appendingPathComponent("Project", isDirectory: true)
        let inner = outer.appendingPathComponent("Build", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)

        let loc = location(id: "derivedData", tier: .regen, roots: [root])

        #expect(throws: DeletionPlanningError.nestedTargets(outer: "Project", inner: "Build")) {
            try DeletionPlanner.children([child(outer), child(inner)], in: loc, context: PlanningContext())
        }
        #expect(FileManager.default.fileExists(atPath: inner.path))
    }

    @Test("A shared name prefix is not treated as nesting")
    func siblingPrefixIsNotNesting() throws {
        let root = try makeRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let foo = root.appendingPathComponent("Foo", isDirectory: true)
        let fooBar = root.appendingPathComponent("FooBar", isDirectory: true)
        try FileManager.default.createDirectory(at: foo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fooBar, withIntermediateDirectories: true)

        let loc = location(id: "derivedData", tier: .regen, roots: [root])
        let plan = try DeletionPlanner.children([child(foo), child(fooBar)], in: loc, context: PlanningContext())

        #expect(plan.count == 2)
    }

    @Test("The new planning errors all have user-facing copy")
    func newErrorsHaveDescriptions() {
        let errors: [DeletionPlanningError] = [
            .duplicateTarget(name: "X"),
            .nestedTargets(outer: "Outer", inner: "Inner"),
            .simulatorNotShutdown(name: "iPhone 17 Pro"),
            .refused(name: "X", error: .symlinkTarget("/x"))
        ]
        for error in errors {
            #expect(!(error.errorDescription ?? "").isEmpty, "\(error)")
        }
        #expect(
            DeletionPlanningError.simulatorNotShutdown(name: "iPhone 17 Pro").errorDescription
                == "iPhone 17 Pro must be shut down before its caches can be cleared."
        )
    }
}
