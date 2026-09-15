import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("DeletionPlanner active-toolchain warning")
struct DeletionPlannerToolchainTests {
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

    private func makeToolchain(under root: URL, identifier: String, named name: String) throws -> URL {
        let toolchain = root.appendingPathComponent("\(name).xctoolchain", isDirectory: true)
        try FileManager.default.createDirectory(at: toolchain, withIntermediateDirectories: true)
        let plist: [String: Any] = ["CFBundleIdentifier": identifier]
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
        try data.write(to: toolchain.appendingPathComponent("Info.plist"))
        return toolchain
    }

    @Test("A toolchain child's consequence warns only for the active bundle")
    func toolchainChildWarnsOnlyWhenActive() throws {
        let root = try makeTempRoot(named: "Toolchains")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        let active = try makeToolchain(under: root, identifier: "org.swift.active", named: "Active")
        let other = try makeToolchain(under: root, identifier: "org.swift.other", named: "Other")

        let loc = location(id: LocationCatalog.toolchains.id, tier: .judgment, roots: [root])
        let activeChild = ChildEntry(
            id: "active", name: "Active.xctoolchain", url: active, reclaimableBytes: 10,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .judgment,
            consequence: "The toolchain must be re-downloaded and re-installed to use it again."
        )
        let otherChild = ChildEntry(
            id: "other", name: "Other.xctoolchain", url: other, reclaimableBytes: 10,
            staleness: StalenessInfo(lastUsedDate: Date()), tier: .judgment,
            consequence: "The toolchain must be re-downloaded and re-installed to use it again."
        )

        let activePlan = try DeletionPlanner.child(
            activeChild, in: loc,
            context: PlanningContext(activeToolchainOverrideIdentifier: "org.swift.active")
        )
        #expect(activePlan.items[0].consequence.hasPrefix("This is the toolchain Xcode is currently set to use."))

        let otherPlan = try DeletionPlanner.child(
            otherChild, in: loc,
            context: PlanningContext(activeToolchainOverrideIdentifier: "org.swift.active")
        )
        #expect(!otherPlan.items[0].consequence.contains("currently set to use"))

        let noOverridePlan = try DeletionPlanner.child(
            activeChild, in: loc,
            context: PlanningContext(activeToolchainOverrideIdentifier: nil)
        )
        #expect(!noOverridePlan.items[0].consequence.contains("currently set to use"))
    }

    @Test("Clearing the whole Toolchains location warns when it holds the active toolchain")
    func wholeToolchainsLocationWarnsWhenActiveInside() throws {
        let root = try makeTempRoot(named: "Toolchains")
        defer { TestFileSystem.removeDirectoryRecursively(at: root.deletingLastPathComponent()) }
        _ = try makeToolchain(under: root, identifier: "org.swift.active", named: "Active")

        let loc = location(id: LocationCatalog.toolchains.id, tier: .judgment, roots: [root])
        let entry = InventoryEntry.sized(
            location: loc,
            reclaimableBytes: 4096,
            staleness: StalenessInfo(lastUsedDate: Date()),
            roots: [RootSize(url: root, allocatedBytes: 4096)]
        )

        let warnedPlan = try DeletionPlanner.wholeLocation(
            entry,
            context: PlanningContext(activeToolchainOverrideIdentifier: "org.swift.active")
        )
        #expect(warnedPlan.items[0].consequence.hasPrefix("This is the toolchain Xcode is currently set to use."))

        let unwarnedPlan = try DeletionPlanner.wholeLocation(
            entry,
            context: PlanningContext(activeToolchainOverrideIdentifier: "org.swift.completely-different")
        )
        #expect(!unwarnedPlan.items[0].consequence.contains("currently set to use"))
    }
}
