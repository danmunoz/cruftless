import CruftlessCore
import Foundation
import Testing

@Suite("Orphaned Derived Data projects through Review")
struct OrphanedProjectDeletionTests {
    /// Not a catalog id, so the executor validates against the plan's own allowlisted roots.
    private func location(_ fixture: DerivedDataFixture) -> TrackedLocation {
        TrackedLocation(
            id: "derivedDataFixture",
            title: "Derived Data",
            icon: .symbol("hammer"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .newestChildMtime,
            resolveRoots: { [fixture.root] }
        )
    }

    private func child(
        _ folder: URL,
        workspace: DerivedDataWorkspace?,
        bytes: Int64 = 4096
    ) -> ChildEntry {
        ChildEntry(
            id: "derivedData-\(folder.lastPathComponent)",
            name: folder.lastPathComponent,
            url: folder,
            reclaimableBytes: bytes,
            staleness: StalenessInfo(lastUsedDate: nil),
            tier: .regen,
            consequence: "Xcode recreates this on the next build.",
            workspace: workspace
        )
    }

    @Test("An orphaned folder's plan carries the re-check precondition")
    func planCarriesPrecondition() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("Gone")
        let folder = try fixture.makeFolder("Gone-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)

        let plan = try DeletionPlanner.children(
            [child(folder, workspace: .orphaned(missing))],
            in: location(fixture),
            context: PlanningContext()
        )

        #expect(plan.items.first?.precondition == .derivedDataProjectMissing(
            folder: folder,
            workspacePath: missing,
            name: "Gone"
        ))
    }

    @Test("A live or unknown folder's plan carries no precondition")
    func liveFolderHasNoPrecondition() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let project = try fixture.makeProject("Live").path(percentEncoded: false)
        let live = try fixture.makeFolder("Live-abcdefghijklmnopqrstuvwxyzab", workspacePath: project)
        let unknown = try fixture.makeFolder("ModuleCache.noindex", workspacePath: nil)

        let plan = try DeletionPlanner.children(
            [child(live, workspace: .live(project)), child(unknown, workspace: .unknown)],
            in: location(fixture),
            context: PlanningContext()
        )

        #expect(plan.items.allSatisfy { $0.precondition == nil })
    }

    @Test("Review refuses to plan a folder whose project came back")
    func planningRefusesRestoredProject() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("Back")
        let folder = try fixture.makeFolder("Back-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)
        try FileManager.default.createDirectory(atPath: missing, withIntermediateDirectories: true)

        #expect(throws: DeletionPlanningError.orphanedProjectChanged(name: "Back")) {
            try DeletionPlanner.children(
                [child(folder, workspace: .orphaned(missing))],
                in: location(fixture),
                context: PlanningContext()
            )
        }
    }

    @Test("Review refuses to plan a folder that now records another project")
    func planningRefusesRewrittenRecord() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("Old")
        let folder = try fixture.makeFolder("Old-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)
        try fixture.writeInfoPlist(["WorkspacePath": fixture.missingProject("Other")], in: folder)

        #expect(throws: DeletionPlanningError.orphanedProjectChanged(name: "Old")) {
            try DeletionPlanner.child(
                child(folder, workspace: .orphaned(missing)),
                in: location(fixture),
                context: PlanningContext()
            )
        }
    }

    @Test("A project restored after Review stops the delete")
    func executorRefusesRestoredProject() async throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("Restored")
        let folder = try fixture.makeFolder("Restored-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)
        let plan = try DeletionPlanner.children(
            [child(folder, workspace: .orphaned(missing))],
            in: location(fixture),
            context: PlanningContext()
        )

        try FileManager.default.createDirectory(atPath: missing, withIntermediateDirectories: true)
        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)

        #expect(result.failedCount == 1)
        #expect(result.items[0].status.failureReason?.contains("no longer confirmed missing") == true)
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test("A plist removed after Review stops the delete")
    func executorRefusesUnreadableRecord() async throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("NoRecord")
        let folder = try fixture.makeFolder("NoRecord-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)
        let plan = try DeletionPlanner.children(
            [child(folder, workspace: .orphaned(missing))],
            in: location(fixture),
            context: PlanningContext()
        )

        TestFileSystem.removeFile(at: folder.appendingPathComponent("info.plist"))
        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)

        #expect(result.failedCount == 1)
        #expect(FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test("A project still missing at execute time is cleared")
    func executorClearsStillOrphaned() async throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("StillGone")
        let folder = try fixture.makeFolder("StillGone-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)
        let plan = try DeletionPlanner.children(
            [child(folder, workspace: .orphaned(missing))],
            in: location(fixture),
            context: PlanningContext()
        )

        let result = await DeletionExecutor(simulatorExecutor: MockSimulatorExecutor()).execute(plan)

        #expect(result.allSucceeded)
        #expect(!FileManager.default.fileExists(atPath: folder.path(percentEncoded: false)))
    }

    @Test("The suggestion covers only orphaned, selectable folders")
    func suggestionSelectsOrphans() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let orphanA = child(fixture.root.appendingPathComponent("A"), workspace: .orphaned("/gone/A.xcodeproj"), bytes: 100)
        let orphanB = child(fixture.root.appendingPathComponent("B"), workspace: .orphaned("/gone/B.xcodeproj"), bytes: 50)
        let protected = child(fixture.root.appendingPathComponent("P"), workspace: .orphaned("/gone/P.xcodeproj"))
        let live = child(fixture.root.appendingPathComponent("L"), workspace: .live("/here/L.xcodeproj"))
        let unknown = child(fixture.root.appendingPathComponent("U"), workspace: .unknown)
        let policy = ProtectedPaths(customProtectedPaths: [protected.url])

        let suggestion = try #require(OrphanedProjectsSuggestion(
            children: [orphanA, orphanB, protected, live, unknown],
            protectedPaths: policy
        ))

        #expect(suggestion.childIDs == [orphanA.id, orphanB.id])
        #expect(suggestion.count == 2)
        #expect(suggestion.reclaimableBytes == 150)
        #expect(OrphanedProjectsSuggestion(children: [live, unknown], protectedPaths: .default) == nil)
    }

    @Test("Selecting the suggestion replaces the selection with eligible rows only")
    func selectionReplacement() {
        let items = [
            CleanupSelectionItem(id: "a", reclaimableBytes: 1, isSelectable: true),
            CleanupSelectionItem(id: "b", reclaimableBytes: 1, isSelectable: false, disabledReason: "protected"),
            CleanupSelectionItem(id: "c", reclaimableBytes: 1, isSelectable: true)
        ]
        var selection = CleanupSelection(selectedIDs: ["c"])

        selection.replace(with: ["a", "b", "missing"], among: items)

        #expect(selection.selectedIDs == ["a"])
    }
}
