import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("PathGuard Hardening Tests")
struct PathGuardHardeningTests {
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("A root of / is dropped, so nothing is admitted under it")
    func slashRootIsDropped() throws {
        let guardInstance = PathGuard(roots: [URL(fileURLWithPath: "/")])
        #expect(guardInstance.roots.isEmpty)

        let victim = URL(fileURLWithPath: "/Volumes/Work/Projects/precious")
        #expect(throws: PathGuardError.outsideAllowlistedRoots(ProtectedPaths.normalize(victim))) {
            _ = try guardInstance.validate(victim)
        }
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(URL(fileURLWithPath: "/Users/someone/Projects/precious"))
        }
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validateRoot(URL(fileURLWithPath: "/"))
        }
    }

    @Test("A denylisted directory is dropped as a root")
    func protectedRootIsDropped() {
        let home = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        let roots = [
            home,
            home.appendingPathComponent("Library"),
            URL(fileURLWithPath: "/Users"),
            URL(fileURLWithPath: "/usr/local"),
            URL(fileURLWithPath: "/Applications/Xcode.app")
        ]
        let guardInstance = PathGuard(roots: roots)
        #expect(guardInstance.roots.isEmpty)
    }

    @Test("A root inside a user-protected path is dropped")
    func rootInsideCustomProtectedIsDropped() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let root = base.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)

        let policy = ProtectedPaths(customProtectedPaths: [base])
        let guardInstance = PathGuard(roots: [root], protectedPaths: policy)
        #expect(guardInstance.roots.isEmpty)
    }

    @Test("The app's real roots all survive root sanitising")
    func catalogRootsAreUsable() {
        let policy = ProtectedPaths()
        for location in LocationCatalog.all where location.tier.isDeletable {
            for root in location.resolveRoots() {
                #expect(policy.isUsableRoot(root), "\(location.id): \(root.path)")
            }
        }

        for location in [LocationCatalog.simulatorDyldCache, LocationCatalog.xcodeInstalls] {
            for root in location.resolveRoots() {
                #expect(!policy.isUsableRoot(root), "\(location.id): \(root.path)")
            }
        }
    }

    @Test("Nested roots never let validate admit the inner root")
    func nestedRootsRefuseInnerRoot() throws {
        let outer = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: outer) }
        let inner = outer.appendingPathComponent("inner", isDirectory: true)
        try FileManager.default.createDirectory(at: inner, withIntermediateDirectories: true)

        for roots in [[outer, inner], [inner, outer]] {
            let guardInstance = PathGuard(roots: roots)
            #expect(throws: PathGuardError.matchesRootItself(ProtectedPaths.normalize(inner))) {
                _ = try guardInstance.validate(inner)
            }
        }
    }

    @Test("A user-protected descendant vetoes a child delete")
    func protectedDescendantVetoesChild() throws {
        let root = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let project = root.appendingPathComponent("MyApp-abc", isDirectory: true)
        let checkouts = project.appendingPathComponent("SourcePackages/checkouts", isDirectory: true)
        try FileManager.default.createDirectory(at: checkouts, withIntermediateDirectories: true)

        let policy = ProtectedPaths(customProtectedPaths: [checkouts])
        let guardInstance = PathGuard(roots: [root], protectedPaths: policy)

        #expect(throws: PathGuardError.containsProtectedDescendant(ProtectedPaths.normalize(project))) {
            _ = try guardInstance.validate(project)
        }

        let other = root.appendingPathComponent("Other-def", isDirectory: true)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        _ = try guardInstance.validate(other)
    }

    @Test("CoreSimulator device-set structure is refused by both entry points")
    func coreSimulatorStructureRefused() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let devices = base.appendingPathComponent("CoreSimulator/Devices", isDirectory: true)
        let device = devices.appendingPathComponent("11111111-2222-3333-4444-555555555555", isDirectory: true)
        let data = device.appendingPathComponent("data", isDirectory: true)
        let tmp = data.appendingPathComponent("tmp", isDirectory: true)
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
        try "{}".write(to: device.appendingPathComponent("device.plist"), atomically: true, encoding: .utf8)

        let wide = PathGuard(roots: [base])
        for refused in [devices, device, data, device.appendingPathComponent("device.plist")] {
            #expect(throws: PathGuardError.protectedPath(ProtectedPaths.normalize(refused))) {
                _ = try wide.validate(refused)
            }
        }
        let devicesRoot = PathGuard(roots: [devices])
        #expect(throws: PathGuardError.protectedPath(ProtectedPaths.normalize(devices))) {
            _ = try devicesRoot.validateRoot(devices)
        }
        #expect(throws: PathGuardError.self) {
            _ = try devicesRoot.validate(device)
        }

        let bloat = PathGuard(roots: [data])
        #expect(bloat.roots.count == 1)
        let validated = try bloat.validate(tmp)
        #expect(validated.path == ProtectedPaths.normalize(tmp))
    }

    @Test("Structure rule matches by depth, not by exact spelling")
    func structureRuleShape() {
        let home = NSHomeDirectory()
        func inHome(_ suffix: String) -> String {
            (home as NSString).appendingPathComponent(suffix)
        }

        let admitted = [
            inHome("Library/Developer/CoreSimulator/Devices/UDID/data/tmp"),
            inHome("Library/Developer/CoreSimulator/Devices/UDID/data/Library/Caches"),
            inHome("Library/Developer/CoreSimulator/Caches/dyld"),
            inHome("Library/Developer/Xcode/DerivedData/Devices")
        ]
        let refused = [
            inHome("Library/Developer/CoreSimulator/Devices"),
            inHome("Library/Developer/CoreSimulator/Devices/UDID"),
            inHome("Library/Developer/CoreSimulator/Devices/UDID/data"),
            inHome("Library/Developer/CoreSimulator/Devices/UDID/device.plist"),
            inHome("Library/Developer/coresimulator/devices/UDID/data"),
            "/Volumes/Ext/CoreSimulator/Devices/UDID"
        ]
        let policy = ProtectedPaths()
        for path in admitted {
            #expect(!policy.isProtected(URL(fileURLWithPath: path)), Comment(rawValue: path))
        }
        for path in refused {
            #expect(policy.isProtected(URL(fileURLWithPath: path)), Comment(rawValue: path))
        }
    }

    @Test("System denylist is case-insensitive")
    func denylistIsCaseInsensitive() {
        let policy = ProtectedPaths()
        let home = NSHomeDirectory()
        let spellings = [
            "/system/library/frameworks",
            "/USR/bin",
            "/applications/Xcode.app",
            "/users",
            home.uppercased(),
            (home as NSString).appendingPathComponent("library").lowercased()
        ]
        for path in spellings {
            #expect(policy.isProtected(URL(fileURLWithPath: path)), Comment(rawValue: path))
        }
    }

    @Test("A user-protected path is matched case-insensitively")
    func customProtectedIsCaseInsensitive() {
        let policy = ProtectedPaths(customProtectedPaths: [URL(fileURLWithPath: "/tmp/Keep/Me")])
        #expect(policy.isProtected(URL(fileURLWithPath: "/tmp/keep/me/file")))
        #expect(policy.containsCustomProtectedPath(in: URL(fileURLWithPath: "/tmp/KEEP")))
    }

    @Test("A NUL byte in the target is refused")
    func nulByteRefused() throws {
        let root = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let target = root.appendingPathComponent("child\u{0}evil")
        let guardInstance = PathGuard(roots: [root])
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(target)
        }
    }
}
