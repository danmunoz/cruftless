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
            walk.rootSizes.append(RootSize(url: root, allocatedBytes: result.allocatedBytes))
            walk.breakdowns[ProtectedPaths.normalize(root)] = breakdown.sizes

            if result.unreadableDirectoryCount > 0, walk.incomplete == nil {
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

    static func incompleteScanReason(root: URL, result: SizeResult) -> String {
        let count = result.unreadableDirectoryCount
        let folders = count == 1 ? "1 folder" : "\(count) folders"
        let rootPath = ProtectedPaths.normalize(root)
        let first = result.firstUnreadablePath ?? rootPath
        return "\(folders) could not be read under \(rootPath); sizes are incomplete (first: \(first))"
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
