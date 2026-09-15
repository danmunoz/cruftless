import CoreServices
import Foundation

public protocol FilesystemWatcher: Sendable {
    func startMonitoring(paths: [String], onChange: @escaping @Sendable (String) -> Void)
    func stopMonitoring()
}

public final class DefaultFSEventsWatcher: FilesystemWatcher, @unchecked Sendable {
    private var streamRef: FSEventStreamRef?
    private let queue = DispatchQueue(label: "com.danmunoz.cruftless.fsevents", qos: .utility)

    public init() {}

    public func startMonitoring(paths: [String], onChange: @escaping @Sendable (String) -> Void) {
        stopMonitoring()
        guard !paths.isEmpty else { return }

        var context = FSEventStreamContext(
            version: 0,
            info: Unmanaged.passRetained(Box(onChange)).toOpaque(),
            retain: nil,
            release: { info in
                guard let info else { return }
                Unmanaged<Box<@Sendable (String) -> Void>>.fromOpaque(info).release()
            },
            copyDescription: nil
        )

        let callback: FSEventStreamCallback = { _, clientCallBackInfo, _, eventPaths, _, _ in
            guard let clientCallBackInfo else { return }
            let handler = Unmanaged<Box<@Sendable (String) -> Void>>.fromOpaque(clientCallBackInfo).takeUnretainedValue().value
            let paths = Unmanaged<CFArray>.fromOpaque(eventPaths).takeUnretainedValue()
            for case let path as String in paths as NSArray {
                handler(path)
            }
        }

        let flags = UInt32(kFSEventStreamCreateFlagUseCFTypes | kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagNoDefer)
        let stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            callback,
            &context,
            paths as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            1.0, // latency: 1s coalesce
            flags
        )

        guard let validStream = stream else { return }
        streamRef = validStream
        FSEventStreamSetDispatchQueue(validStream, queue)
        FSEventStreamStart(validStream)
    }

    public func stopMonitoring() {
        if let streamRef {
            FSEventStreamStop(streamRef)
            FSEventStreamInvalidate(streamRef)
            FSEventStreamRelease(streamRef)
            self.streamRef = nil
        }
    }

    deinit {
        stopMonitoring()
    }
}

private final class Box<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) {
        self.value = value
    }
}

/// One watched filesystem root, tagged with the tracked location that owns it.
public struct WatchedRoot: Sendable, Hashable {
    public let locationId: String
    public let url: URL

    public init(locationId: String, url: URL) {
        self.locationId = locationId
        self.url = url
    }
}

package struct ResolvedRoot: Sendable, Hashable {
    package let path: String
    package let locationId: String

    package init(path: String, locationId: String) {
        self.path = path
        self.locationId = locationId
    }
}

/// What a filesystem event invalidated.
public enum InvalidationScope: Sendable, Hashable {
    /// The tracked locations owning the roots the event landed under.
    case locations(Set<String>)
    /// The event could not be attributed to any watched root, so nothing is known to still be valid.
    case everything

    /// Union of two scopes.
    public func merged(with other: InvalidationScope) -> InvalidationScope {
        switch (self, other) {
        case (.everything, _), (_, .everything):
            .everything
        case let (.locations(mine), .locations(theirs)):
            .locations(mine.union(theirs))
        }
    }
}

/// Manages filesystem monitoring over tracked roots to invalidate cached scan inventories.
public final class FSEventsInvalidator: @unchecked Sendable {
    public static let defaultDebounce: DispatchTimeInterval = .seconds(3)

    /// Keys the pending-work table.
    private enum DebounceKey: Hashable {
        case location(String)
        case everything
    }

    private let watcher: any FilesystemWatcher
    private let onInvalidate: @Sendable (InvalidationScope) -> Void
    private let debounce: DispatchTimeInterval
    private let queue = DispatchQueue(label: "com.danmunoz.cruftless.fsevents.debounce")
    private let lock = NSLock()
    private var isMonitoring = false
    private var pendingWorkItems: [DebounceKey: DispatchWorkItem] = [:]

    /// Watched roots as resolved, absolute paths paired with their owning location.
    private var watchedRoots: [ResolvedRoot] = []

    public init(
        watcher: any FilesystemWatcher? = nil,
        debounce: DispatchTimeInterval = FSEventsInvalidator.defaultDebounce,
        onInvalidate: @escaping @Sendable (InvalidationScope) -> Void
    ) {
        self.watcher = watcher ?? DefaultFSEventsWatcher()
        self.debounce = debounce
        self.onInvalidate = onInvalidate
    }

    public func startMonitoring(roots: [WatchedRoot]) {
        lock.lock()
        defer { lock.unlock() }

        var resolved: [ResolvedRoot] = []
        for root in roots {
            let path = Self.withoutTrailingSlash(
                root.url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            )
            guard FileManager.default.fileExists(atPath: path) else { continue }
            resolved.append(ResolvedRoot(path: path, locationId: root.locationId))
        }

        guard !resolved.isEmpty else { return }
        watchedRoots = resolved.sorted { $0.path.count > $1.path.count }

        var seen: Set<String> = []
        let paths = watchedRoots.map(\.path).filter { seen.insert($0).inserted }

        watcher.startMonitoring(paths: paths) { [weak self] path in
            self?.handleEvent(path: path)
        }
        isMonitoring = true
    }

    /// Attributes one event to the locations it invalidated, then debounces.
    private func handleEvent(path: String) {
        lock.lock()
        let scope = Self.scope(forEventPath: path, watchedRoots: watchedRoots)
        lock.unlock()
        scheduleInvalidate(scope)
    }

    /// The locations owning the watched roots `path` sits under.
    package static func scope(
        forEventPath path: String,
        watchedRoots: [ResolvedRoot]
    ) -> InvalidationScope {
        let path = withoutTrailingSlash(path)
        var ids: Set<String> = []
        for root in watchedRoots where path == root.path || path.hasPrefix(root.path + "/") {
            ids.insert(root.locationId)
        }
        return ids.isEmpty ? .everything : .locations(ids)
    }

    static func withoutTrailingSlash(_ path: String) -> String {
        var trimmed = path
        while trimmed.count > 1, trimmed.hasSuffix("/") {
            trimmed.removeLast()
        }
        return trimmed
    }

    private func scheduleInvalidate(_ scope: InvalidationScope) {
        let keys: [DebounceKey]
        switch scope {
        case .everything:
            keys = [.everything]
        case let .locations(ids):
            keys = ids.map(DebounceKey.location)
        }

        lock.lock()
        if case .everything = scope {
            // A full rescan covers every pending per-location one.
            for (_, item) in pendingWorkItems { item.cancel() }
            pendingWorkItems.removeAll()
        }

        var scheduled: [DispatchWorkItem] = []
        for key in keys {
            pendingWorkItems[key]?.cancel()
            let firing: InvalidationScope = switch key {
            case .everything: .everything
            case let .location(id): .locations([id])
            }
            let item = DispatchWorkItem { [weak self] in
                guard let self else { return }
                lock.lock()
                pendingWorkItems[key] = nil
                lock.unlock()
                onInvalidate(firing)
            }
            pendingWorkItems[key] = item
            scheduled.append(item)
        }
        lock.unlock()

        for item in scheduled {
            queue.asyncAfter(deadline: .now() + debounce, execute: item)
        }
    }

    public func stopMonitoring() {
        lock.lock()
        defer { lock.unlock() }
        for (_, item) in pendingWorkItems { item.cancel() }
        pendingWorkItems.removeAll()
        watchedRoots = []
        if isMonitoring {
            watcher.stopMonitoring()
            isMonitoring = false
        }
    }

    deinit {
        stopMonitoring()
    }
}
