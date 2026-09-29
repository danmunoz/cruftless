@testable import CruftlessCore
import CruftlessFixtures
import Darwin
import Foundation
import Testing

@Suite("Android Studio index path capability")
struct AndroidStudioIndexPathTests {
    @Test("Accepts only the exact default versioned index directory")
    func acceptsExactDefaultIndex() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let policy = fixture.policy()

        #expect(AndroidStudioIndexPath.validate(index, home: fixture.home, protectedPaths: policy) == index)
        #expect(AndroidStudioIndexPath.validate(
            fixture.studioRoot,
            home: fixture.home,
            protectedPaths: policy
        ) == nil)
        #expect(AndroidStudioIndexPath.validate(
            fixture.studioRoot.appendingPathComponent("LocalHistory", isDirectory: true),
            home: fixture.home,
            protectedPaths: policy
        ) == nil)
        #expect(AndroidStudioIndexPath.validate(
            fixture.studioRoot.appendingPathComponent("plugins", isDirectory: true),
            home: fixture.home,
            protectedPaths: policy
        ) == nil)
        #expect(AndroidStudioIndexPath.validate(
            fixture.home.appendingPathComponent("Library/Caches/Google/AndroidStudioBackup/index", isDirectory: true),
            home: fixture.home,
            protectedPaths: policy
        ) == nil)
    }

    @Test("Rejects symlinked index paths and redirected Studio system paths")
    func rejectsSymlinksAndRedirects() throws {
        let symlinkFixture = try Fixture()
        defer { symlinkFixture.remove() }
        _ = symlinkFixture.makeDirectory("Library/Caches/Google")
        let external = symlinkFixture.makeDirectory("outside/index")
        let linkedStudioRoot = symlinkFixture.googleRoot.appendingPathComponent("AndroidStudio2025.2", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: linkedStudioRoot, withDestinationURL: external.deletingLastPathComponent())

        #expect(AndroidStudioIndexPath.validate(
            linkedStudioRoot.appendingPathComponent("index", isDirectory: true),
            home: symlinkFixture.home,
            protectedPaths: symlinkFixture.policy()
        ) == nil)

        let redirectFixture = try Fixture()
        defer { redirectFixture.remove() }
        let redirectedRoot = redirectFixture.makeDirectory("outside/system")
        let config = redirectFixture.makeDirectory("Library/Application Support/Google/AndroidStudio2025.2")
        try "idea.system.path=\(redirectedRoot.path)\n"
            .write(to: config.appendingPathComponent("idea.properties"), atomically: true, encoding: .utf8)
        let ordinary = redirectFixture.makeDirectory("Library/Caches/Google/AndroidStudio2025.2/index")
        #expect(AndroidStudioIndexPath.validate(
            ordinary,
            home: redirectFixture.home,
            protectedPaths: redirectFixture.policy()
        ) == nil)
    }

    @Test("Rejects custom protected descendants and paths belonging to another home")
    func rejectsCustomProtectedPathsAndOtherHomes() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let protectedDescendant = index.appendingPathComponent("keep", isDirectory: true)
        let policy = ProtectedPaths(customProtectedPaths: [protectedDescendant], home: fixture.home)

        #expect(AndroidStudioIndexPath.validate(index, home: fixture.home, protectedPaths: policy) == nil)
        let exactTargetPolicy = ProtectedPaths(customProtectedPaths: [index], home: fixture.home)
        #expect(AndroidStudioIndexPath.validate(index, home: fixture.home, protectedPaths: exactTargetPolicy) == nil)
        let parentPolicy = ProtectedPaths(customProtectedPaths: [fixture.studioRoot], home: fixture.home)
        #expect(AndroidStudioIndexPath.validate(index, home: fixture.home, protectedPaths: parentPolicy) == nil)

        let otherHome = fixture.base.appendingPathComponent("another-user", isDirectory: true)
        let otherIndex = otherHome.appendingPathComponent("Library/Caches/Google/AndroidStudio2025.1/index", isDirectory: true)
        #expect(AndroidStudioIndexPath.validate(otherIndex, home: fixture.home, protectedPaths: fixture.policy()) == nil)
    }

    @Test("Rejects a mounted child path")
    func rejectsMountedChildPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let policy = fixture.policy()
        let realDevice = Self.deviceNumber

        let result = AndroidStudioIndexPath.validate(
            index,
            home: fixture.home,
            protectedPaths: policy,
            deviceNumberReader: { url in
                guard let device = realDevice(url) else { return nil }
                return url.lastPathComponent == "index" ? device &+ 1 : device
            }
        )
        #expect(result == nil)
    }

    private static func deviceNumber(_ url: URL) -> UInt64? {
        var info = stat()
        guard lstat(url.path(percentEncoded: false), &info) == 0 else { return nil }
        return UInt64(info.st_dev)
    }

    private struct Fixture {
        let base: URL
        var home: URL { base.appendingPathComponent("home", isDirectory: true) }
        var googleRoot: URL { home.appendingPathComponent("Library/Caches/Google", isDirectory: true) }
        var studioRoot: URL { googleRoot.appendingPathComponent("AndroidStudio2025.1", isDirectory: true) }

        init() throws {
            base = URL(fileURLWithPath: ProtectedPaths.normalize(FileManager.default.temporaryDirectory), isDirectory: true)
                .appendingPathComponent("cruftless-studio-index-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        }

        func makeDirectory(_ relativePath: String) -> URL {
            let url = home.appendingPathComponent(relativePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func makeIndex() throws -> URL {
            let index = makeDirectory("Library/Caches/Google/AndroidStudio2025.1/index")
            _ = makeDirectory("Library/Caches/Google/AndroidStudio2025.1/LocalHistory")
            _ = makeDirectory("Library/Caches/Google/AndroidStudio2025.1/plugins")
            return index
        }

        func policy() -> ProtectedPaths {
            ProtectedPaths(customProtectedPaths: [], home: home)
        }

        func remove() {
            TestFileSystem.removeDirectoryRecursively(at: base)
        }
    }
}
