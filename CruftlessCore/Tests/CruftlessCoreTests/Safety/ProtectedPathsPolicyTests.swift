import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("ProtectedPaths policy")
struct ProtectedPathsPolicyTests {
    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("A structural anchor inside the target vetoes the delete")
    func structuralAnchorVetoesTarget() throws {
        let root = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let home = root.appendingPathComponent("home", isDirectory: true)
        let developer = home.appendingPathComponent("Library/Developer", isDirectory: true)
        try FileManager.default.createDirectory(
            at: developer.appendingPathComponent("CoreSimulator", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: developer.appendingPathComponent("Xcode/Archives", isDirectory: true),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: developer.appendingPathComponent("Xcode/UserData", isDirectory: true),
            withIntermediateDirectories: true
        )

        let policy = ProtectedPaths(customProtectedPaths: [], home: home)
        for holder in [developer, developer.appendingPathComponent("Xcode", isDirectory: true)] {
            #expect(policy.containsProtectedDescendant(in: holder), "\(holder.path)")
            #expect(!policy.isUsableRoot(holder), "\(holder.path)")
        }

        let archives = developer.appendingPathComponent("Xcode/Archives", isDirectory: true)
        #expect(!policy.containsProtectedDescendant(in: archives))
        #expect(policy.isUsableRoot(archives))

        let previews = developer.appendingPathComponent("Xcode/UserData/Previews", isDirectory: true)
        #expect(policy.isUsableRoot(previews))
    }

    @Test("A nested device set is refused by the inner match, not the outer one")
    func nestedDeviceSetRefused() {
        let policy = ProtectedPaths()
        let outer = "/private/tmp/cruftless-nested/CoreSimulator/Devices/UDID-A/data/Nested"
        let inner = outer + "/CoreSimulator/Devices/UDID-B"

        for path in [inner, inner + "/data"] {
            #expect(policy.isProtected(URL(fileURLWithPath: path)), Comment(rawValue: path))
        }
        for path in [outer, inner + "/data/tmp"] {
            #expect(!policy.isProtected(URL(fileURLWithPath: path)), Comment(rawValue: path))
        }
    }

    @Test(
        "System directories added to the denylist are protected in both spellings",
        arguments: [
            "/etc/hosts",
            "/private/etc/hosts",
            "/opt/homebrew/bin",
            "/var/db/dslocal",
            "/private/var/db/dslocal",
            "/var/root/Library",
            "/private/var/root/Library",
            "/var/log/system.log",
            "/private/var/log/system.log",
            "/Library/Developer/CoreSimulator/Caches/dyld",
            "/library/preferences",
            "/Volumes",
            "/Volumes/Ext",
            "/volumes/ext"
        ]
    )
    func extendedDenylist(path: String) {
        let policy = ProtectedPaths()
        let url = URL(fileURLWithPath: path)
        #expect(policy.isProtected(url), Comment(rawValue: path))
        #expect(!policy.isUsableRoot(url), Comment(rawValue: path))
    }

    @Test("Per-user temporary directories stay usable")
    func temporaryDirectoriesUsable() throws {
        let temp = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: temp) }
        let policy = ProtectedPaths()
        #expect(!policy.isProtected(temp))
        #expect(policy.isUsableRoot(temp))
        #expect(!policy.isProtected(URL(fileURLWithPath: "/Volumes/Ext/DerivedData")))
    }

    @Test("Another account's home folder is protected, this one's contents are not")
    func foreignUserFoldersProtected() {
        let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)
        let policy = ProtectedPaths(customProtectedPaths: [], home: home)

        for path in ["/Users", "/Users/tester", "/Users/someoneelse", "/Users/someoneelse/Projects", "/Users/Shared"] {
            #expect(policy.isProtected(URL(fileURLWithPath: path)), Comment(rawValue: path))
        }
        #expect(!policy.isProtected(URL(fileURLWithPath: "/Users/tester/Developer/Build")))

        let sandboxed = ProtectedPaths(
            customProtectedPaths: [],
            home: URL(fileURLWithPath: "/Users/tester/Library/Containers/app/Data", isDirectory: true)
        )
        #expect(!sandboxed.isProtected(URL(fileURLWithPath: "/Users/tester/Developer/Build")))
        #expect(sandboxed.isProtected(URL(fileURLWithPath: "/Users/someoneelse/Projects")))
    }

    @Test("Normalization agrees between an existing path and its absent children")
    func normalizationIsDeterministic() throws {
        let root = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let existing = URL(fileURLWithPath: "/tmp", isDirectory: true)
        let absentChild = existing.appendingPathComponent("cruftless-absent/deeper", isDirectory: true)
        #expect(ProtectedPaths.normalize(absentChild)
            == ProtectedPaths.normalize(existing) + "/cruftless-absent/deeper")

        #expect(ProtectedPaths.normalize(URL(fileURLWithPath: "/tmp/a/../b"))
            == ProtectedPaths.normalize(URL(fileURLWithPath: "/tmp/b")))
        #expect(ProtectedPaths.normalize(URL(fileURLWithPath: "/", isDirectory: true)) == "/")
        #expect(!ProtectedPaths.normalize(root).hasSuffix("/"))

        let guardInstance = PathGuard(roots: [root])
        let absent = root.appendingPathComponent("not-created-yet/child", isDirectory: true)
        #expect(try guardInstance.validate(absent).path == ProtectedPaths.normalize(absent))
    }

    @Test("A file URL with a host is refused")
    func hostedFileURLRefused() throws {
        let root = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let guardInstance = PathGuard(roots: [root])

        let hosted = try #require(URL(string: "file://evil.example.com/etc/passwd"))
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validate(hosted)
        }
        #expect(throws: PathGuardError.self) {
            _ = try guardInstance.validateRoot(hosted)
        }
    }
}
