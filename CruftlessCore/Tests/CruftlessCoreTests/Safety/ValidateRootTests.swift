import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("PathGuard.validateRoot Safety Tests")
struct ValidateRootTests {
    private func makeTempRoot() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("Admits an allowlisted root exactly")
    func admitsExactRoot() throws {
        let root = try makeTempRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let guardInstance = PathGuard(roots: [root])
        let validated = try guardInstance.validateRoot(root)
        #expect(validated.path == ProtectedPaths.normalize(root))
    }

    @Test("Refuses anything inside a root: only the root itself qualifies")
    func refusesChildren() throws {
        let root = try makeTempRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let child = root.appendingPathComponent("ModuleCache.noindex", isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)

        let guardInstance = PathGuard(roots: [root])
        #expect(throws: PathGuardError.self) {
            try guardInstance.validateRoot(child)
        }
    }

    @Test("Refuses a sibling that merely shares a prefix with the root")
    func refusesSiblingPrefix() throws {
        let base = try makeTempRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("bar", isDirectory: true)
        let sibling = base.appendingPathComponent("barbaz", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: sibling, withIntermediateDirectories: true)

        let guardInstance = PathGuard(roots: [root])
        #expect(throws: PathGuardError.self) {
            try guardInstance.validateRoot(sibling)
        }
    }

    @Test("Refuses the filesystem root even when it is allowlisted")
    func refusesFilesystemRoot() {
        let slash = URL(fileURLWithPath: "/", isDirectory: true)
        let guardInstance = PathGuard(roots: [slash])
        #expect(throws: PathGuardError.protectedPath("/")) {
            try guardInstance.validateRoot(slash)
        }
    }

    @Test("Refuses a denylisted system directory even when it is allowlisted")
    func refusesDenylistedRoot() {
        for path in ["/System", "/Library", "/Applications", "/usr", "/Users"] {
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let guardInstance = PathGuard(roots: [url])
            #expect(throws: PathGuardError.self, "expected \(path) to be refused") {
                try guardInstance.validateRoot(url)
            }
        }
    }

    @Test("Refuses a root that contains a user-protected path")
    func refusesRootWithProtectedDescendant() throws {
        let root = try makeTempRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let keep = root.appendingPathComponent("KeepThis", isDirectory: true)
        try FileManager.default.createDirectory(at: keep, withIntermediateDirectories: true)

        let guardInstance = PathGuard(
            roots: [root],
            protectedPaths: ProtectedPaths(customProtectedPaths: [keep])
        )

        #expect(throws: PathGuardError.self) {
            try guardInstance.validateRoot(root)
        }
    }

    @Test("Refuses a path that is not an allowlisted root at all")
    func refusesUnknownRoot() throws {
        let root = try makeTempRoot()
        let other = try makeTempRoot()
        defer {
            TestFileSystem.removeDirectoryRecursively(at: root)
            TestFileSystem.removeDirectoryRecursively(at: other)
        }

        let guardInstance = PathGuard(roots: [root])
        #expect(throws: PathGuardError.self) {
            try guardInstance.validateRoot(other)
        }
    }

    @Test("Refuses relative and empty targets")
    func refusesRelativeTargets() throws {
        let root = try makeTempRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let guardInstance = PathGuard(roots: [root])
        #expect(throws: PathGuardError.self) {
            try guardInstance.validateRoot(URL(fileURLWithPath: "relative/path"))
        }
    }

    @Test("Every deletable catalog root round-trips, siblings still refused")
    func catalogRootsRoundTrip() throws {
        for location in LocationCatalog.all where location.tier.isDeletable {
            for root in location.resolveRoots() {
                let guardInstance = PathGuard(roots: [root])

                if location.mutationPolicy == .simctl {
                    #expect(throws: PathGuardError.self, "\(location.id) must never be path-deleted") {
                        try guardInstance.validateRoot(root)
                    }
                } else {
                    let validated = try guardInstance.validateRoot(root)
                    #expect(validated.path == ProtectedPaths.normalize(root), "\(location.id)")
                }

                let sibling = root.deletingLastPathComponent()
                    .appendingPathComponent(root.lastPathComponent + "-evil", isDirectory: true)
                #expect(throws: PathGuardError.self, "\(location.id) admitted a sibling") {
                    try guardInstance.validateRoot(sibling)
                }
            }
        }
    }

    @Test("Refuses a root that holds a device set, Archives, or UserData")
    func refusesRootHoldingStructuralAnchor() throws {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let developer = home.appendingPathComponent("Library/Developer", isDirectory: true)
        let xcode = developer.appendingPathComponent("Xcode", isDirectory: true)

        for candidate in [developer, xcode] {
            let policy = ProtectedPaths()
            #expect(policy.containsProtectedDescendant(in: candidate), "\(candidate.path)")
            #expect(!policy.isUsableRoot(candidate), "\(candidate.path)")

            let guardInstance = PathGuard(roots: [candidate])
            #expect(guardInstance.roots.isEmpty)
            #expect(throws: PathGuardError.notAnAllowlistedRoot(ProtectedPaths.normalize(candidate))) {
                try guardInstance.validateRoot(candidate)
            }
        }

        let archives = RootResolver.defaultArchivesRoot(home: home)
        #expect(ProtectedPaths().isUsableRoot(archives))
    }

    @Test("Refuses a target whose final component is a symlink")
    func refusesSymlinkFinalComponent() throws {
        let base = try makeTempRoot()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let root = base.appendingPathComponent("Toolchains", isDirectory: true)
        let real = root.appendingPathComponent("swift-6.4.xctoolchain", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = root.appendingPathComponent("swift-latest.xctoolchain", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        let guardInstance = PathGuard(roots: [root])
        #expect(throws: PathGuardError.symlinkTarget(ProtectedPaths.standardize(link))) {
            _ = try guardInstance.validate(link)
        }
        #expect(try guardInstance.validate(real).path == ProtectedPaths.normalize(real))

        let linkedRoot = base.appendingPathComponent("Alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedRoot, withDestinationURL: root)
        let aliasGuard = PathGuard(roots: [linkedRoot])
        #expect(throws: PathGuardError.symlinkTarget(ProtectedPaths.standardize(linkedRoot))) {
            try aliasGuard.validateRoot(linkedRoot)
        }
    }
}
