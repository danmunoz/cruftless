@testable import CruftlessCore
import Foundation
import Synchronization

/// A stand-in home folder with its own access ledger, so its protected areas are test folders, never the real ones.
struct AccessFixture {
    let home: URL
    let defaults: UserDefaults
    let ledger: AccessLedger
    let gate: AccessGate
    private let suiteName: String

    init(volumes: @escaping ProtectedAreaClassifier.VolumeInspector = { _ in nil }) throws {
        // Under the real home but outside every real protected area, so Android's same-home and symlink-free root rules hold.
        let base = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
            .appendingPathComponent(".cruftless-access-test-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        home = URL(fileURLWithPath: PathNormalizer.normalize(base.path(percentEncoded: false)), isDirectory: true)
        suiteName = "cruftless-access-tests-\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else { throw FixtureError() }
        self.defaults = defaults
        ledger = AccessLedger(userDefaults: defaults)
        gate = AccessGate(classifier: ProtectedAreaClassifier(home: home, inspectVolume: volumes), ledger: ledger)
    }

    /// Creates `relativePath` under the fake home and returns it.
    @discardableResult
    func directory(_ relativePath: String) throws -> URL {
        let url = home.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    /// Writes `bytes` of payload at `relativePath` under the fake home.
    func file(_ relativePath: String, bytes: Int = 4096) throws {
        let url = home.appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: bytes).write(to: url)
    }

    func remove() {
        TestFileSystem.removeDirectoryRecursively(at: home)
        defaults.removePersistentDomain(forName: suiteName)
    }
}

private struct FixtureError: Error {}

/// Collects every open and listing the audit seam reports while it is alive.
final class FileAccessRecorder: Sendable {
    private final class Log: Sendable {
        let events = Mutex<[FileAccessEvent]>([])
    }

    private let log: Log
    private let token: UInt64

    init() {
        let log = Log()
        self.log = log
        token = FileAccessAudit.observe { event in log.events.withLock { $0.append(event) } }
    }

    func stop() {
        FileAccessAudit.stopObserving(token)
    }

    /// Every recorded event, in order.
    var all: [FileAccessEvent] {
        log.events.withLock { $0 }
    }

    /// Opens and listings at or under `url`.
    func events(under url: URL) -> [FileAccessEvent] {
        let root = PathNormalizer.normalize(url.path(percentEncoded: false))
        return all.filter { event in
            [event.path, PathNormalizer.normalize(event.path)].contains { $0 == root || $0.hasPrefix(root + "/") }
        }
    }
}
