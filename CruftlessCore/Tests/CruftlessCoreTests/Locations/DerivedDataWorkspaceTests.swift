import CruftlessCore
import Foundation
import Synchronization
import Testing

@Suite("Derived Data workspace classification")
struct DerivedDataWorkspaceTests {
    private func derivedData(_ fixture: DerivedDataFixture) -> TrackedLocation {
        TrackedLocation(
            id: LocationCatalog.derivedData.id,
            title: "Derived Data",
            icon: .symbol("hammer"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .newestChildMtime,
            resolveRoots: { [fixture.root] }
        )
    }

    @Test("A workspace that still exists is live")
    func liveWorkspace() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let project = try fixture.makeProject("App").path(percentEncoded: false)
        let folder = try fixture.makeFolder("App-abcdefghijklmnopqrstuvwxyzab", workspacePath: project)

        #expect(DerivedDataWorkspaceReader.classify(folder: folder) == .live(project))
    }

    @Test("A workspace that no longer exists is orphaned")
    func orphanedWorkspace() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("Old")
        let folder = try fixture.makeFolder("Old-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)

        #expect(DerivedDataWorkspaceReader.classify(folder: folder) == .orphaned(missing))
    }

    @Test("A binary info.plist is read like an XML one")
    func binaryPlist() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let missing = fixture.missingProject("Binary")
        let folder = try fixture.makeFolder(
            "Binary-abcdefghijklmnopqrstuvwxyzab",
            workspacePath: missing,
            format: .binary
        )
        let header = try Data(contentsOf: folder.appendingPathComponent("info.plist")).prefix(6)

        #expect(header == Data("bplist".utf8))
        #expect(DerivedDataWorkspaceReader.classify(folder: folder) == .orphaned(missing))
    }

    @Test("A missing info.plist is unknown")
    func missingPlist() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let folder = try fixture.makeFolder("NoPlist-abcdefghijklmnopqrstuvwxyzab", workspacePath: nil)

        #expect(DerivedDataWorkspaceReader.classify(folder: folder) == .unknown)
    }

    @Test("An unreadable or malformed info.plist is unknown")
    func unreadablePlist() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let garbage = try fixture.makeFolder("Garbage-abcdefghijklmnopqrstuvwxyzab", workspacePath: nil)
        try Data("not a plist".utf8).write(to: garbage.appendingPathComponent("info.plist"))
        let wrongType = try fixture.makeFolder("WrongType-abcdefghijklmnopqrstuvwxyzab", workspacePath: nil)
        try fixture.writeInfoPlist(["WorkspacePath": 42], in: wrongType)
        let empty = try fixture.makeFolder("Empty-abcdefghijklmnopqrstuvwxyzab", workspacePath: "")

        #expect(DerivedDataWorkspaceReader.classify(folder: garbage) == .unknown)
        #expect(DerivedDataWorkspaceReader.classify(folder: wrongType) == .unknown)
        #expect(DerivedDataWorkspaceReader.classify(folder: empty) == .unknown)
    }

    @Test("A relative workspace path is unknown, never orphaned")
    func relativePath() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let relative = try fixture.makeFolder("Relative-abcdefghijklmnopqrstuvwxyzab", workspacePath: "Gone/App.xcodeproj")
        let tilde = try fixture.makeFolder("Tilde-abcdefghijklmnopqrstuvwxyzab", workspacePath: "~/Gone/App.xcodeproj")

        #expect(DerivedDataWorkspaceReader.classify(folder: relative) == .unknown)
        #expect(DerivedDataWorkspaceReader.classify(folder: tilde) == .unknown)
        #expect(DerivedDataWorkspaceReader.classify(workspacePath: "/") == .unknown)
    }

    @Test("A workspace on an unmounted volume is unknown")
    func unmountedVolume() {
        let path = "/Volumes/Cruftless-\(UUID().uuidString)/Projects/App.xcodeproj"

        #expect(DerivedDataWorkspaceReader.classify(workspacePath: path) == .unknown)
        #expect(DerivedDataWorkspaceReader.classify(workspacePath: path, isVolumeMounted: { _ in false }) == .unknown)
    }

    @Test("A missing workspace on a mounted volume is orphaned")
    func mountedVolumeMissingProject() {
        let path = "/Volumes/External/Projects/App.xcodeproj"
        let asked = LockedPaths()

        let workspace = DerivedDataWorkspaceReader.classify(workspacePath: path) { volume in
            asked.append(volume)
            return true
        }

        #expect(workspace == .orphaned(path))
        #expect(asked.values == ["/Volumes/External"])
    }

    @Test("Only a real mount point counts as a mounted volume")
    func mountPointDetection() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }

        #expect(DerivedDataWorkspaceReader.isMountPoint("/"))
        #expect(!DerivedDataWorkspaceReader.isMountPoint(fixture.root.path(percentEncoded: false)))
        #expect(!DerivedDataWorkspaceReader.isMountPoint("/Volumes/Cruftless-\(UUID().uuidString)"))
    }

    @Test("The drill-down classifies project folders and leaves system folders unknown")
    func drillDownCarriesWorkspace() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        let project = try fixture.makeProject("Live").path(percentEncoded: false)
        let missing = fixture.missingProject("Gone")
        try fixture.makeFolder("Live-abcdefghijklmnopqrstuvwxyzab", workspacePath: project)
        try fixture.makeFolder("Gone-abcdefghijklmnopqrstuvwxyzab", workspacePath: missing)
        try fixture.makeFolder("ModuleCache.noindex", workspacePath: nil)

        let children = DrillDownProvider.loadChildren(for: derivedData(fixture))
        let byName = Dictionary(uniqueKeysWithValues: children.map { ($0.name, $0) })

        #expect(byName["Live-abcdefghijklmnopqrstuvwxyzab"]?.workspace == .live(project))
        #expect(byName["Gone-abcdefghijklmnopqrstuvwxyzab"]?.workspace == .orphaned(missing))
        #expect(byName["Gone-abcdefghijklmnopqrstuvwxyzab"]?.consequence.contains("no longer exists") == true)
        #expect(byName["ModuleCache.noindex"]?.workspace == .unknown)
        #expect(byName["Live-abcdefghijklmnopqrstuvwxyzab"]?.consequence == "Xcode recreates this on the next build.")
    }

    @Test("Other locations never read an info.plist")
    func otherLocationsSkipWorkspace() throws {
        let fixture = try DerivedDataFixture()
        defer { TestFileSystem.removeDirectoryRecursively(at: fixture.base) }
        try fixture.makeFolder("Gone-abcdefghijklmnopqrstuvwxyzab", workspacePath: fixture.missingProject("Gone"))
        let location = TrackedLocation(
            id: "swiftPMCache",
            title: "SwiftPM",
            icon: .symbol("shippingbox"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            resolveRoots: { [fixture.root] }
        )

        #expect(DrillDownProvider.loadChildren(for: location).allSatisfy { $0.workspace == nil })
    }

    @Test("Paths in the home folder are shown with a tilde")
    func tildeAbbreviation() {
        #expect(Naming.abbreviatingHome(in: "/Users/dan/Repos/App.xcodeproj", home: "/Users/dan") == "~/Repos/App.xcodeproj")
        #expect(Naming.abbreviatingHome(in: "/Users/dan", home: "/Users/dan/") == "~")
        #expect(Naming.abbreviatingHome(in: "/Users/daniel/App.xcodeproj", home: "/Users/dan") == "/Users/daniel/App.xcodeproj")
        #expect(Naming.abbreviatingHome(in: "/Volumes/X/App.xcodeproj", home: "/Users/dan") == "/Volumes/X/App.xcodeproj")
        #expect(Naming.abbreviatingHome(in: "/tmp/App.xcodeproj", home: "/") == "/tmp/App.xcodeproj")
    }
}

/// Records the volumes a mount check was asked about.
private final class LockedPaths: Sendable {
    private let storage = Mutex<[String]>([])

    var values: [String] {
        storage.withLock { $0 }
    }

    func append(_ path: String) {
        storage.withLock { $0.append(path) }
    }
}
