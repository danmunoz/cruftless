import Darwin
import Foundation

/// The read-only half of a scan: which roots can be walked, what walking them produced, and how that is reported.
extension ScanEngine {
    /// Splits roots into the ones that can actually be read and a reason when none of them can.
    static func readableRoots(among roots: [URL]) -> (roots: [URL], unreadableReason: String?) {
        var existing: [URL] = []
        var unreadableReason: String?

        for root in roots {
            let path = root.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
            guard FileManager.default.fileExists(atPath: path) else { continue }

            if FileManager.default.isReadableFile(atPath: path) {
                existing.append(root)
            } else {
                unreadableReason = "Permission denied reading \(path)"
            }
        }

        return (existing, unreadableReason)
    }

    /// Whether this location will produce a row at all, judged without walking anything.
    static func willProduceRow(_ location: TrackedLocation, roots: [URL]) -> Bool {
        switch location.sizeSource {
        case .simulatorRuntimes:
            true
        case .filesystemRoots:
            roots.contains { FileManager.default.fileExists(atPath: ProtectedPaths.normalize($0)) }
                || location.discoveryIssue() != nil
        }
    }

    /// What walking one location's roots produced.
    struct RootsWalk {
        var totalAllocated: Int64 = 0
        var newestMtime: Date?
        var rootSizes: [RootSize] = []
        /// Resolved root path -> every path measured under it -> its size.
        var breakdowns: [String: [String: SizeResult]] = [:]
        /// The first root whose walk could not read every folder under it.
        var incomplete: (root: URL, result: SizeResult)?
    }

    static func walkRoots(
        _ location: TrackedLocation,
        _ roots: [URL],
        inodeSet: InodeSet,
        recordingDepth: Int = 1
    ) -> RootsWalk {
        var walk = RootsWalk()

        for root in roots {
            let breakdown = DirectoryWalker.walkWithChildren(
                url: root,
                inodeSet: inodeSet,
                recordingDepth: recordingDepth
            )
            let result = breakdown.total

            walk.totalAllocated += result.allocatedBytes
            walk.rootSizes.append(rootSize(root, bytes: result.allocatedBytes, location: location))
            walk.breakdowns[ProtectedPaths.normalize(root)] = breakdown.sizes

            if result.unreadableDirectoryCount > 0 || result.skippedMountCount > 0, walk.incomplete == nil {
                walk.incomplete = (root, result)
            }

            if let mtime = result.newestMtime {
                if let current = walk.newestMtime {
                    if mtime > current { walk.newestMtime = mtime }
                } else {
                    walk.newestMtime = mtime
                }
            }
        }

        return walk
    }

    private static func rootSize(_ root: URL, bytes: Int64, location: TrackedLocation) -> RootSize {
        guard location.platform == .android else { return RootSize(url: root, allocatedBytes: bytes) }
        var rootStat = stat()
        let volume = lstat(ProtectedPaths.normalize(root), &rootStat) == 0 ? String(rootStat.st_dev) : nil
        return RootSize(
            url: root,
            allocatedBytes: bytes,
            source: RootResolver.androidRootSource(locationID: location.id, root: root),
            volumeIdentifier: volume,
            layout: RootResolver.androidRootLayout(locationID: location.id, root: root)
        )
    }

    package static func incompleteScanReason(root: URL, result: SizeResult) -> String {
        let rootPath = ProtectedPaths.normalize(root)
        var reasons: [String] = []
        if result.unreadableDirectoryCount > 0 {
            let count = result.unreadableDirectoryCount
            let folders = count == 1 ? "1 folder" : "\(count) folders"
            reasons.append("\(folders) could not be read (first: \(result.firstUnreadablePath ?? rootPath))")
        }
        if result.skippedMountCount > 0 {
            let count = result.skippedMountCount
            let volumes = count == 1 ? "1 nested volume was" : "\(count) nested volumes were"
            reasons.append("\(volumes) skipped (first: \(result.firstSkippedMountPath ?? rootPath))")
        }
        return "\(reasons.joined(separator: "; ")) under \(rootPath); sizes are incomplete"
    }

    static func incompleteReason(for location: TrackedLocation, walk: RootsWalk) -> String? {
        let issues = [
            location.discoveryIssue(),
            walk.incomplete.map { incompleteScanReason(root: $0.root, result: $0.result) }
        ].compactMap(\.self)
        return issues.isEmpty ? nil : issues.joined(separator: " ")
    }

    static func staleness(
        for location: TrackedLocation,
        roots: [URL],
        newestMtime: Date?
    ) -> StalenessInfo {
        Staleness.resolve(
            source: location.stalenessSource,
            archiveCreationDate: roots
                .compactMap { ArchiveDates.newestCreationDate(under: $0) }
                .max(),
            simulatorLastUsedAt: roots
                .flatMap { DeviceStore.loadDevices(from: $0) }
                .compactMap(\.lastUsedAt)
                .max(),
            newestChildMtime: newestMtime,
            topLevelMtime: newestMtime
        )
    }
}
