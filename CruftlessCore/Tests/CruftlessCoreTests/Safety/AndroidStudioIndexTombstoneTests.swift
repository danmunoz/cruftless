@testable import CruftlessCore
import CruftlessFixtures
import Darwin
import Foundation
import Testing

@Suite("Android Studio index tombstone recovery")
struct AndroidStudioIndexTombstoneTests {
    @Test("A crash before rename leaves a prepared, non-actionable record")
    func preparedRecord() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let recordURL = try fixture.prepare(index)

        #expect(fixture.inspect().first == .init(recordURL: recordURL, state: .prepared))
    }

    @Test("Preparation refuses arbitrary directories and protected Studio paths")
    func prepareRequiresValidatedDefaultPath() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let arbitrary = fixture.makeDirectory("projects/AndroidStudio2025.1/index")
        let arbitraryFingerprint = try #require(Fingerprint.capture(at: arbitrary))
        #expect(throws: AndroidStudioIndexTombstone.StoreError.self) {
            try AndroidStudioIndexTombstone.prepare(
                source: arbitrary,
                fingerprint: arbitraryFingerprint,
                versionDirectory: arbitrary.deletingLastPathComponent(),
                context: fixture.context
            )
        }

        let index = try fixture.makeIndex()
        let protected = ProtectedPaths(customProtectedPaths: [fixture.versionDirectory], home: fixture.home)
        #expect(throws: AndroidStudioIndexTombstone.StoreError.self) {
            try AndroidStudioIndexTombstone.prepare(
                source: index,
                fingerprint: try #require(Fingerprint.capture(at: index)),
                versionDirectory: fixture.versionDirectory,
                context: .init(home: fixture.home, protectedPaths: protected, recordDirectory: fixture.recordDirectory)
            )
        }
    }

    @Test("The recovery store is restricted to owned, exact Application Support")
    func recoveryStoreMustBeExactAndUnredirected() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let fingerprint = try #require(Fingerprint.capture(at: index))
        let wrongStore = fixture.base.appendingPathComponent("elsewhere", isDirectory: true)
        try FileManager.default.createDirectory(at: wrongStore, withIntermediateDirectories: true)
        let wrongContext = AndroidStudioIndexTombstone.Context(
            home: fixture.home,
            protectedPaths: fixture.policy(),
            recordDirectory: wrongStore
        )
        #expect(throws: AndroidStudioIndexTombstone.StoreError.self) {
            try AndroidStudioIndexTombstone.prepare(
                source: index,
                fingerprint: fingerprint,
                versionDirectory: fixture.versionDirectory,
                context: wrongContext
            )
        }

        let recordStorePath = fixture.recordDirectory.path(percentEncoded: false)
        #expect(chmod(recordStorePath, 0o775) == 0)
        #expect(throws: AndroidStudioIndexTombstone.StoreError.self) {
            try AndroidStudioIndexTombstone.prepare(
                source: index,
                fingerprint: fingerprint,
                versionDirectory: fixture.versionDirectory,
                context: fixture.context
            )
        }
        #expect(chmod(recordStorePath, 0o755) == 0)

        let realStore = fixture.recordDirectory
        let movedStore = realStore.deletingLastPathComponent().appendingPathComponent("recovery-store", isDirectory: true)
        try FileManager.default.moveItem(at: realStore, to: movedStore)
        try FileManager.default.createSymbolicLink(at: realStore, withDestinationURL: movedStore)
        #expect(throws: AndroidStudioIndexTombstone.StoreError.self) {
            try AndroidStudioIndexTombstone.prepare(
                source: index,
                fingerprint: fingerprint,
                versionDirectory: fixture.versionDirectory,
                context: fixture.context
            )
        }
    }

    @Test("A crash after rename recovers only the recorded inode even after index recreation")
    func renamedRecordSurvivesReplacement() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let original = try fixture.makeIndex()
        let originalFingerprint = try #require(Fingerprint.capture(at: original))
        let recordURL = try AndroidStudioIndexTombstone.prepare(
            source: original,
            fingerprint: originalFingerprint,
            versionDirectory: fixture.versionDirectory,
            context: fixture.context
        )
        let token = try #require(AndroidStudioIndexTombstone.token(from: recordURL.lastPathComponent))
        let tombstone = fixture.versionDirectory.appendingPathComponent(
            AndroidStudioIndexTombstone.tombstoneName(token),
            isDirectory: true
        )
        try FileManager.default.moveItem(at: original, to: tombstone)
        let replacement = fixture.makeDirectory("Library/Caches/Google/AndroidStudio2025.1/index")
        try "new cache".write(to: replacement.appendingPathComponent("new"), atomically: true, encoding: .utf8)

        #expect(fixture.inspect().first == .init(recordURL: recordURL, state: .pending(tombstone)))
        #expect(ProtectedPaths.normalize(replacement) != ProtectedPaths.normalize(tombstone))
    }

    @Test("A partially removed tombstone remains discoverable with its original identity")
    func partialDeletionRemainsPending() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let nested = fixture.makeDirectory("Library/Caches/Google/AndroidStudio2025.1/index/nested")
        try "old data".write(to: nested.appendingPathComponent("data"), atomically: true, encoding: .utf8)
        let recordURL = try fixture.prepare(index)
        let token = try #require(AndroidStudioIndexTombstone.token(from: recordURL.lastPathComponent))
        let tombstone = fixture.versionDirectory.appendingPathComponent(
            AndroidStudioIndexTombstone.tombstoneName(token),
            isDirectory: true
        )
        try FileManager.default.moveItem(at: index, to: tombstone)
        TestFileSystem.removeDirectoryRecursively(at: tombstone.appendingPathComponent("nested"))

        #expect(fixture.inspect().first == .init(recordURL: recordURL, state: .pending(tombstone)))
    }

    @Test("A missing tombstone is completed and a tampered identity is stale")
    func completedAndTamperedRecords() throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        let index = try fixture.makeIndex()
        let completedRecord = try fixture.prepare(index)
        let completedToken = try #require(AndroidStudioIndexTombstone.token(from: completedRecord.lastPathComponent))
        let completedTombstone = fixture.versionDirectory.appendingPathComponent(
            AndroidStudioIndexTombstone.tombstoneName(completedToken),
            isDirectory: true
        )
        try FileManager.default.moveItem(at: index, to: completedTombstone)
        TestFileSystem.removeDirectoryRecursively(at: completedTombstone)
        #expect(fixture.inspect().first == .init(recordURL: completedRecord, state: .completed))

        let secondIndex = try fixture.makeIndex()
        let staleRecord = try fixture.prepare(secondIndex)
        let record = try #require(AndroidStudioIndexTombstone.readRecord(at: staleRecord))
        let tampered = AndroidStudioIndexTombstone.Record(
            schemaVersion: record.schemaVersion,
            token: record.token,
            versionDirectoryPath: record.versionDirectoryPath,
            sourceInode: record.sourceInode &+ 1,
            sourceDevice: record.sourceDevice,
            sourceBirthTimeSeconds: record.sourceBirthTimeSeconds,
            sourceBirthTimeNanoseconds: record.sourceBirthTimeNanoseconds
        )
        try JSONEncoder().encode(tampered).write(to: staleRecord, options: .atomic)
        let recoveredStaleState = fixture.inspect()
            .first { ProtectedPaths.normalize($0.recordURL) == ProtectedPaths.normalize(staleRecord) }?.state
        #expect(recoveredStaleState == .stale)

        let thirdIndex = try fixture.makeIndex()
        let generationRecordURL = try fixture.prepare(thirdIndex)
        let generationRecord = try #require(AndroidStudioIndexTombstone.readRecord(at: generationRecordURL))
        let reusedInode = AndroidStudioIndexTombstone.Record(
            schemaVersion: generationRecord.schemaVersion,
            token: generationRecord.token,
            versionDirectoryPath: generationRecord.versionDirectoryPath,
            sourceInode: generationRecord.sourceInode,
            sourceDevice: generationRecord.sourceDevice,
            sourceBirthTimeSeconds: generationRecord.sourceBirthTimeSeconds &+ 1,
            sourceBirthTimeNanoseconds: generationRecord.sourceBirthTimeNanoseconds
        )
        try JSONEncoder().encode(reusedInode).write(to: generationRecordURL, options: .atomic)
        let generationState = fixture.inspect()
            .first { ProtectedPaths.normalize($0.recordURL) == ProtectedPaths.normalize(generationRecordURL) }?.state
        #expect(generationState == .stale)
    }

    private struct Fixture {
        let base: URL
        var home: URL { base.appendingPathComponent("home", isDirectory: true) }
        var versionDirectory: URL {
            home.appendingPathComponent("Library/Caches/Google/AndroidStudio2025.1", isDirectory: true)
        }
        var recordDirectory: URL { AndroidStudioIndexTombstone.recordDirectory(for: home) }
        var context: AndroidStudioIndexTombstone.Context {
            .init(home: home, protectedPaths: policy(), recordDirectory: recordDirectory)
        }

        init() throws {
            base = URL(fileURLWithPath: ProtectedPaths.normalize(FileManager.default.temporaryDirectory), isDirectory: true)
                .appendingPathComponent("cruftless-index-recovery-\(UUID().uuidString)", isDirectory: true)
            try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: recordDirectory, withIntermediateDirectories: true)
        }

        func makeIndex() throws -> URL {
            let index = makeDirectory("Library/Caches/Google/AndroidStudio2025.1/index")
            try "cached index".write(to: index.appendingPathComponent("data"), atomically: true, encoding: .utf8)
            return index
        }

        func makeDirectory(_ relativePath: String) -> URL {
            let url = home.appendingPathComponent(relativePath, isDirectory: true)
            try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url
        }

        func prepare(_ index: URL) throws -> URL {
            try AndroidStudioIndexTombstone.prepare(
                source: index,
                fingerprint: try #require(Fingerprint.capture(at: index)),
                versionDirectory: versionDirectory,
                context: context
            )
        }

        func inspect() -> [AndroidStudioIndexTombstone.Inspection] {
            AndroidStudioIndexTombstone.inspect(
                versionDirectory: versionDirectory,
                context: context
            ) ?? []
        }

        func policy() -> ProtectedPaths {
            ProtectedPaths(customProtectedPaths: [], home: home)
        }

        func remove() {
            TestFileSystem.removeDirectoryRecursively(at: base)
        }
    }
}
