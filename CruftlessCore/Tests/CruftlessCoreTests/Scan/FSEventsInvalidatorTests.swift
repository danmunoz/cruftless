import CruftlessCore
import Foundation
import Testing

private final class MockFilesystemWatcher: FilesystemWatcher, @unchecked Sendable {
    var monitoredPaths: [String] = []
    var changeHandler: (@Sendable (String) -> Void)?
    var isStopped = false

    func startMonitoring(paths: [String], onChange: @escaping @Sendable (String) -> Void) {
        monitoredPaths = paths
        changeHandler = onChange
        isStopped = false
    }

    func stopMonitoring() {
        isStopped = true
    }

    func simulateChange(path: String) {
        changeHandler?(path)
    }
}

@Suite("FSEventsInvalidator Tests")
struct FSEventsInvalidatorTests {
    @Test("Filesystem event triggers invalidation callback")
    func fSEventsInvalidation() async throws {
        let mockWatcher = MockFilesystemWatcher()
        let invalidated = LockedCounter()

        let invalidator = FSEventsInvalidator(watcher: mockWatcher, debounce: .milliseconds(30)) { _ in
            invalidated.increment()
        }

        let tempURL = FileManager.default.temporaryDirectory
        invalidator.startMonitoring(roots: [WatchedRoot(locationId: "derivedData", url: tempURL)])

        #expect(invalidated.invocations == 0)
        mockWatcher.simulateChange(path: tempURL.resolvingSymlinksInPath().path)
        try await Task.sleep(for: .milliseconds(200))
        #expect(invalidated.invocations == 1)

        invalidator.stopMonitoring()
        #expect(mockWatcher.isStopped)
    }

    @Test("A burst of events coalesces into one invalidation")
    func fSEventsBurstCoalesces() async throws {
        let mockWatcher = MockFilesystemWatcher()
        let invalidated = LockedCounter()

        let invalidator = FSEventsInvalidator(watcher: mockWatcher, debounce: .milliseconds(60)) { _ in
            invalidated.increment()
        }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        invalidator.startMonitoring(roots: [WatchedRoot(locationId: "derivedData", url: root)])

        for index in 0 ..< 500 {
            mockWatcher.simulateChange(path: root.appendingPathComponent("build-\(index)").path)
        }

        try await Task.sleep(for: .milliseconds(300))
        #expect(invalidated.invocations == 1)
        invalidator.stopMonitoring()
    }

    @Test("Stopping monitoring cancels a pending invalidation")
    func fSEventsStopCancelsPending() async throws {
        let mockWatcher = MockFilesystemWatcher()
        let invalidated = LockedCounter()

        let invalidator = FSEventsInvalidator(watcher: mockWatcher, debounce: .milliseconds(150)) { _ in
            invalidated.increment()
        }
        let root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
        invalidator.startMonitoring(roots: [WatchedRoot(locationId: "derivedData", url: root)])
        mockWatcher.simulateChange(path: root.appendingPathComponent("x").path)
        invalidator.stopMonitoring()

        try await Task.sleep(for: .milliseconds(300))
        #expect(invalidated.invocations == 0)
    }

    @Test("Replacing a scope discards callbacks captured by the previous watcher")
    func replacedScopeRejectsStaleWatcherCallback() async throws {
        let mockWatcher = MockFilesystemWatcher()
        let invalidated = LockedCounter()
        let invalidator = FSEventsInvalidator(watcher: mockWatcher, debounce: .milliseconds(30)) { _ in
            invalidated.increment()
        }
        let root = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        invalidator.replaceMonitoring(
            roots: [WatchedRoot(locationId: "derivedData", url: root)],
            policyGeneration: 1
        )
        let oldHandler = try #require(mockWatcher.changeHandler)
        invalidator.replaceMonitoring(
            roots: [WatchedRoot(locationId: "archives", url: root)],
            policyGeneration: 2
        )

        oldHandler(root.appendingPathComponent("old-scope").path)
        try await Task.sleep(for: .milliseconds(100))

        #expect(invalidated.invocations == 0)
        invalidator.stopMonitoring()
    }

    // MARK: - Scoping

    private static func makeBase() throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-scope-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.resolvingSymlinksInPath()
    }

    private static func makeChild(of base: URL, named name: String) throws -> URL {
        let child = base.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: child, withIntermediateDirectories: true)
        return child
    }

    @Test("An event is attributed to the location owning the root it landed under")
    func eventScopesToOneLocation() async throws {
        let mockWatcher = MockFilesystemWatcher()
        let scopes = LockedScopes()
        let invalidator = FSEventsInvalidator(watcher: mockWatcher, debounce: .milliseconds(30)) {
            scopes.append($0)
        }

        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let derived = try Self.makeChild(of: base, named: "DerivedData")
        let archives = try Self.makeChild(of: base, named: "Archives")

        invalidator.startMonitoring(roots: [
            WatchedRoot(locationId: "derivedData", url: derived),
            WatchedRoot(locationId: "archives", url: archives)
        ])

        mockWatcher.simulateChange(path: derived.appendingPathComponent("MyApp-abc/Build/x.o").path)
        try await Task.sleep(for: .milliseconds(200))

        #expect(scopes.values == [.locations(["derivedData"])])
        invalidator.stopMonitoring()
    }

    @Test("A noisy location does not delay a quiet one's invalidation")
    func perLocationDebounceIsIndependent() async throws {
        let mockWatcher = MockFilesystemWatcher()
        let scopes = LockedScopes()
        let invalidator = FSEventsInvalidator(watcher: mockWatcher, debounce: .milliseconds(250)) {
            scopes.append($0)
        }

        let base = try Self.makeBase()
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let derived = try Self.makeChild(of: base, named: "DerivedData")
        let devices = try Self.makeChild(of: base, named: "Devices")

        invalidator.startMonitoring(roots: [
            WatchedRoot(locationId: "derivedData", url: derived),
            WatchedRoot(locationId: "simulatorDevices", url: devices)
        ])

        let burstPath = derived.appendingPathComponent("MyApp/x.o").path
        let burst = Task {
            for _ in 0 ..< 50 {
                mockWatcher.simulateChange(path: burstPath)
                try? await Task.sleep(for: .milliseconds(20))
            }
        }
        defer { burst.cancel() }

        mockWatcher.simulateChange(path: devices.appendingPathComponent("udid/data/x").path)

        var delivered: [InvalidationScope] = []
        for _ in 0 ..< 28 where delivered.isEmpty {
            try await Task.sleep(for: .milliseconds(25))
            delivered = scopes.values
        }

        #expect(delivered.first == .locations(["simulatorDevices"]))
        invalidator.stopMonitoring()
    }

    @Test("A sibling sharing a root's name prefix is not attributed to it")
    func siblingPrefixIsNotAMatch() {
        let roots = [ResolvedRoot(path: "/foo/bar", locationId: "derivedData")]
        #expect(FSEventsInvalidator.scope(forEventPath: "/foo/barbaz/x", watchedRoots: roots) == .everything)
        #expect(FSEventsInvalidator.scope(forEventPath: "/foo/bar/x", watchedRoots: roots) == .locations(["derivedData"]))
        #expect(FSEventsInvalidator.scope(forEventPath: "/foo/bar", watchedRoots: roots) == .locations(["derivedData"]))
    }

    @Test("A nested root invalidates every location containing the path")
    func nestedRootsInvalidateBoth() {
        let roots = [
            ResolvedRoot(path: "/dev/Xcode/DerivedData", locationId: "derivedData"),
            ResolvedRoot(path: "/dev/Xcode", locationId: "outer")
        ]
        let scope = FSEventsInvalidator.scope(forEventPath: "/dev/Xcode/DerivedData/x", watchedRoots: roots)
        #expect(scope == .locations(["derivedData", "outer"]))
    }

    @Test("An unattributable path invalidates everything")
    func unknownPathInvalidatesEverything() {
        let roots = [ResolvedRoot(path: "/dev/Xcode/DerivedData", locationId: "derivedData")]
        #expect(FSEventsInvalidator.scope(forEventPath: "/somewhere/else", watchedRoots: roots) == .everything)
    }

    @Test("A full invalidation absorbs the per-location ones it subsumes")
    func everythingAbsorbsLocations() {
        #expect(InvalidationScope.locations(["a"]).merged(with: .locations(["b"])) == .locations(["a", "b"]))
        #expect(InvalidationScope.locations(["a"]).merged(with: .everything) == .everything)
        #expect(InvalidationScope.everything.merged(with: .locations(["a"])) == .everything)
    }

    @Test("Real FSEvents watcher decodes event paths without crashing", .timeLimit(.minutes(1)))
    func defaultWatcherDeliversPaths() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-fsevents-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let watcher = DefaultFSEventsWatcher()
        let received = LockedPaths()
        watcher.startMonitoring(paths: [root.resolvingSymlinksInPath().path]) { path in
            received.append(path)
        }
        defer { watcher.stopMonitoring() }

        for _ in 0 ..< 40 where received.paths.isEmpty {
            try Data("cruft".utf8).write(to: root.appendingPathComponent("\(UUID().uuidString).txt"))
            try await Task.sleep(for: .milliseconds(250))
        }

        let paths = received.paths
        #expect(!paths.isEmpty, "FSEvents delivered no paths for a watched directory")
        #expect(paths.allSatisfy { $0.hasPrefix("/") })
        #expect(paths.contains { $0.hasSuffix(".txt") })
    }
}

private final class LockedScopes: @unchecked Sendable {
    private var value: [InvalidationScope] = []
    private let lock = NSLock()

    var values: [InvalidationScope] {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func append(_ scope: InvalidationScope) {
        lock.lock()
        defer { lock.unlock() }
        value.append(scope)
    }
}

private final class LockedPaths: @unchecked Sendable {
    private var value: [String] = []
    private let lock = NSLock()

    var paths: [String] {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func append(_ path: String) {
        lock.lock()
        defer { lock.unlock() }
        value.append(path)
    }
}

private final class LockedCounter: @unchecked Sendable {
    private var value = 0
    private let lock = NSLock()

    var invocations: Int {
        lock.lock()
        defer { lock.unlock() }
        return value
    }

    func increment() {
        lock.lock()
        defer { lock.unlock() }
        value += 1
    }
}

private final class LockedFlag: @unchecked Sendable {
    private var flag = false
    private let lock = NSLock()

    var isSet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return flag
    }

    func set() {
        lock.lock()
        defer { lock.unlock() }
        flag = true
    }
}
