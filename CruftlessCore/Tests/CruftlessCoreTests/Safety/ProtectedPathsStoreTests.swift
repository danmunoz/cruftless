import CruftlessCore
import Foundation
import Testing

@Suite("ProtectedPathsStore")
struct ProtectedPathsStoreTests {
    private func withStore(_ body: (ProtectedPathsStore, UserDefaults) throws -> Void) throws {
        let suiteName = "cruftless.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(ProtectedPathsStore(userDefaults: defaults), defaults)
    }

    private func makeTempDir() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base
    }

    @Test("A path round-trips and protects everything inside it")
    func roundTrip() throws {
        try withStore { store, _ in
            let folder = URL(fileURLWithPath: "/tmp/cruftless-store/Keep", isDirectory: true)
            store.addPath(folder)

            #expect(store.customPaths().count == 1)
            let policy = store.protectedPaths()
            #expect(policy.isProtected(folder))
            #expect(policy.isProtected(folder.appendingPathComponent("inside/file.txt")))
        }
    }

    @Test("A protection on a dangling symlink still matches after the target goes")
    func danglingSymlinkStillMatches() throws {
        let base = try makeTempDir()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }

        let real = base.appendingPathComponent("real", isDirectory: true)
        try FileManager.default.createDirectory(at: real, withIntermediateDirectories: true)
        let link = base.appendingPathComponent("link", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: real)

        try withStore { store, _ in
            store.addPath(link)

            TestFileSystem.removeDirectoryRecursively(at: real)

            let policy = store.protectedPaths()
            #expect(policy.isProtected(link))
            #expect(policy.isProtected(link.appendingPathComponent("child")))
        }
    }

    @Test("A protection on an absent volume still matches")
    func absentVolumeStillMatches() throws {
        try withStore { store, _ in
            let onExternal = URL(fileURLWithPath: "/Volumes/NotMounted/Sacred", isDirectory: true)
            store.addPath(onExternal)

            let policy = store.protectedPaths()
            #expect(policy.isProtected(onExternal))
            #expect(policy.isProtected(onExternal.appendingPathComponent("deep/inside")))
        }
    }

    @Test("Entries are deduplicated case-insensitively and by resolved form")
    func deduplicates() throws {
        try withStore { store, _ in
            store.addPath(URL(fileURLWithPath: "/tmp/cruftless-store/Keep", isDirectory: true))
            store.addPath(URL(fileURLWithPath: "/tmp/cruftless-store/Keep/", isDirectory: true))
            store.addPath(URL(fileURLWithPath: "/private/tmp/cruftless-store/Keep", isDirectory: true))
            store.addPath(URL(fileURLWithPath: "/tmp/cruftless-store/../cruftless-store/Keep", isDirectory: true))
            #expect(store.customPaths().count == 1)

            #expect(store.protectedPaths().customProtectedPaths.count == 1)
        }
    }

    @Test("Entries are stored unresolved, with no trailing slash")
    func storedUnresolved() throws {
        try withStore { store, defaults in
            store.addPath(URL(fileURLWithPath: "/tmp/cruftless-store/Keep/", isDirectory: true))
            let stored = defaults.stringArray(forKey: "cruftless.customProtectedPaths")
            #expect(stored == ["/tmp/cruftless-store/Keep"])
        }
    }

    @Test("Removal matches either spelling")
    func removalMatchesEitherSpelling() throws {
        try withStore { store, _ in
            store.addPath(URL(fileURLWithPath: "/tmp/cruftless-store/Keep", isDirectory: true))
            store.removePath(URL(fileURLWithPath: "/private/tmp/cruftless-store/Keep", isDirectory: true))
            #expect(store.customPaths().isEmpty)

            store.addPath(URL(fileURLWithPath: "/tmp/cruftless-store/Keep", isDirectory: true))
            store.removePath(URL(fileURLWithPath: "/tmp/cruftless-store/Keep/", isDirectory: true))
            #expect(store.customPaths().isEmpty)
        }
    }

    @Test("Legacy resolved entries are read back and deduplicated")
    func legacyEntriesMigrate() throws {
        try withStore { store, defaults in
            defaults.set(
                ["/private/tmp/cruftless-store/Keep", "/tmp/cruftless-store/Keep", ""],
                forKey: "cruftless.customProtectedPaths"
            )
            #expect(store.customPaths().count == 1)
            #expect(store.protectedPaths().isProtected(
                URL(fileURLWithPath: "/tmp/cruftless-store/Keep/inside", isDirectory: true)
            ))
        }
    }
}
