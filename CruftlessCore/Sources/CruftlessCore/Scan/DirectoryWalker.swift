import Darwin
import Foundation

/// A root's total together with the per-path sizes measured underneath it.
public struct ChildBreakdown: Sendable {
    public let total: SizeResult

    public let sizes: [String: SizeResult]

    public init(total: SizeResult, sizes: [String: SizeResult]) {
        self.total = total
        self.sizes = sizes
    }

    public static let empty = ChildBreakdown(total: .zero, sizes: [:])

    /// A root that could not be opened at all: nothing measured, one unreadable directory recorded so the scan can report it.
    public static func unreadableRoot(path: String) -> ChildBreakdown {
        ChildBreakdown(
            total: SizeResult(
                allocatedBytes: 0,
                newestMtime: nil,
                unreadableDirectoryCount: 1,
                firstUnreadablePath: path
            ),
            sizes: [:]
        )
    }
}

/// Fast filesystem walker measuring APFS allocated space.
public enum DirectoryWalker: Sendable {
    /// Walks a file or directory tree, computing total allocated size and newest modification date.
    public static func walk(
        url: URL,
        inodeSet: InodeSet,
        ignoringEntriesCreatedAfter cutoff: Date? = nil
    ) -> SizeResult {
        var accumulator = SizeAccumulator()
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        var rootStat = stat()
        guard lstat(path, &rootStat) == 0 else { return .zero }
        walkInternal(
            path: path,
            inodeSet: inodeSet,
            accumulator: &accumulator,
            cutoff: cutoff,
            rootDevice: UInt64(rootStat.st_dev)
        )
        return accumulator.result()
    }

    public static func walkWithChildren(
        url: URL,
        inodeSet: InodeSet,
        recordingDepth: Int = 1
    ) -> ChildBreakdown {
        let path = ProtectedPaths.normalize(url)

        var rootStat = stat()
        guard lstat(path, &rootStat) == 0 else { return .empty }

        // A bundle is one thing, not a tree to be broken apart.
        guard (rootStat.st_mode & S_IFMT) == S_IFDIR, !AtomicBundles.isAtomicBundle(url) else {
            let total = walk(url: url, inodeSet: inodeSet)
            return ChildBreakdown(total: total, sizes: [path: total])
        }

        guard let dir = opendir(path) else { return .unreadableRoot(path: path) }
        defer { closedir(dir) }

        var sizes: [String: SizeResult] = [:]
        var total = SizeAccumulator()

        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }
            if name == "." || name == ".." { continue }

            let childPath = (path as NSString).appendingPathComponent(name)
            total.add(
                recordedWalk(
                    path: childPath,
                    depth: recordingDepth,
                    inodeSet: inodeSet,
                    rootDevice: UInt64(rootStat.st_dev),
                    into: &sizes
                )
            )
        }

        return ChildBreakdown(total: total.result(), sizes: sizes)
    }

    private static func recordedWalk(
        path: String,
        depth: Int,
        inodeSet: InodeSet,
        rootDevice: UInt64,
        into sizes: inout [String: SizeResult]
    ) -> SizeResult {
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else { return .zero }
        guard UInt64(statBuf.st_dev) == rootDevice else {
            var accumulator = SizeAccumulator()
            if (statBuf.st_mode & S_IFMT) == S_IFDIR {
                accumulator.addSkippedMount(path: path)
            }
            let result = accumulator.result()
            sizes[path] = result
            return result
        }

        let isDirectory = (statBuf.st_mode & S_IFMT) == S_IFDIR
        let isBundle = AtomicBundles.isAtomicBundle(URL(fileURLWithPath: path))

        // A leaf as far as recording goes: one walk, one number.
        guard depth > 1, isDirectory, !isBundle else {
            var accumulator = SizeAccumulator()
            walkInternal(path: path, inodeSet: inodeSet, accumulator: &accumulator, rootDevice: rootDevice)
            let result = accumulator.result()
            sizes[path] = result
            return result
        }

        guard let dir = opendir(path) else {
            var accumulator = SizeAccumulator()
            accumulator.addUnreadableDirectory(path: path)
            let result = accumulator.result()
            sizes[path] = result
            return result
        }
        defer { closedir(dir) }

        var total = SizeAccumulator()
        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }
            if name == "." || name == ".." { continue }

            let childPath = (path as NSString).appendingPathComponent(name)
            total.add(
                recordedWalk(
                    path: childPath,
                    depth: depth - 1,
                    inodeSet: inodeSet,
                    rootDevice: rootDevice,
                    into: &sizes
                )
            )
        }

        // Recorded as well as its children: the level above is still a row wherever a location lists at that level.
        let result = total.result()
        sizes[path] = result
        return result
    }

    private static func walkInternal(
        path: String,
        inodeSet: InodeSet,
        accumulator: inout SizeAccumulator,
        cutoff: Date? = nil,
        rootDevice: UInt64
    ) {
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else {
            return
        }
        guard UInt64(statBuf.st_dev) == rootDevice else {
            if (statBuf.st_mode & S_IFMT) == S_IFDIR {
                accumulator.addSkippedMount(path: path)
            }
            return
        }

        if let cutoff, birthDate(of: statBuf) > cutoff {
            return
        }

        let mode = statBuf.st_mode & S_IFMT
        let mtime = Date(
            timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec) +
                TimeInterval(statBuf.st_mtimespec.tv_nsec) / 1_000_000_000.0
        )

        if mode == S_IFLNK {
            let allocated = Int64(statBuf.st_blocks) * 512
            accumulator.addFile(allocatedBytes: allocated, mtime: mtime)
            return
        }

        if mode == S_IFREG {
            // Hardlink deduplication.
            if statBuf.st_nlink > 1 {
                let isNew = inodeSet.recordHardlinkIfFirstSeen(
                    device: Int32(statBuf.st_dev),
                    inode: UInt64(statBuf.st_ino)
                )
                if !isNew {
                    // Hardlink already counted elsewhere.
                    return
                }
            }

            let allocated = Int64(statBuf.st_blocks) * 512
            accumulator.addFile(allocatedBytes: allocated, mtime: mtime)
            return
        }

        if mode == S_IFDIR {
            walkChildren(
                ofDirectory: path,
                inodeSet: inodeSet,
                accumulator: &accumulator,
                cutoff: cutoff,
                rootDevice: rootDevice
            )
        }
    }

    private static func walkChildren(
        ofDirectory path: String,
        inodeSet: InodeSet,
        accumulator: inout SizeAccumulator,
        cutoff: Date?,
        rootDevice: UInt64
    ) {
        // A directory the app cannot open is not an empty directory.
        guard let dir = opendir(path) else {
            accumulator.addUnreadableDirectory(path: path)
            return
        }
        defer { closedir(dir) }

        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }

            if name == "." || name == ".." {
                continue
            }

            let childPath = (path as NSString).appendingPathComponent(name)
            walkInternal(
                path: childPath,
                inodeSet: inodeSet,
                accumulator: &accumulator,
                cutoff: cutoff,
                rootDevice: rootDevice
            )
        }
    }

    private static func birthDate(of statBuf: stat) -> Date {
        Date(
            timeIntervalSince1970: TimeInterval(statBuf.st_birthtimespec.tv_sec) +
                TimeInterval(statBuf.st_birthtimespec.tv_nsec) / 1_000_000_000.0
        )
    }
}
