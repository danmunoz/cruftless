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

/// Fast filesystem walker measuring APFS allocated space and the clone-aware space a delete would free.
public enum DirectoryWalker: Sendable {
    /// Walks a file or directory tree, computing total allocated size and newest modification date.
    public static func walk(
        url: URL,
        inodeSet: InodeSet,
        ignoringEntriesCreatedAfter cutoff: Date? = nil
    ) -> SizeResult {
        var accumulator = SizeAccumulator()
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let root = DirectoryEntryReader.entry(atPath: path) else { return .zero }
        walkInternal(
            entry: root,
            path: path,
            inodeSet: inodeSet,
            accumulator: &accumulator,
            cutoff: cutoff,
            rootDevice: root.device
        )
        return accumulator.result()
    }

    public static func walkWithChildren(
        url: URL,
        inodeSet: InodeSet,
        recordingDepth: Int = 1
    ) -> ChildBreakdown {
        let path = ProtectedPaths.normalize(url)
        guard let root = DirectoryEntryReader.entry(atPath: path) else { return .empty }

        // A bundle is one thing, not a tree to be broken apart.
        guard root.kind == .directory, !AtomicBundles.isAtomicBundle(url) else {
            let total = walk(url: url, inodeSet: inodeSet)
            return ChildBreakdown(total: total, sizes: [path: total])
        }

        var sizes: [String: SizeResult] = [:]
        var total = SizeAccumulator()
        let readable = DirectoryEntryReader.forEachEntry(inDirectory: path) { child in
            total.merge(
                recordedWalk(
                    (child, DirectoryEntryReader.childPath(path, child.name)),
                    depth: recordingDepth,
                    inodeSet: inodeSet,
                    rootDevice: root.device,
                    into: &sizes
                )
            )
        }
        guard readable || !sizes.isEmpty else { return .unreadableRoot(path: path) }
        if !readable {
            total.addUnreadableDirectory(path: path)
        }

        return ChildBreakdown(total: total.result(), sizes: sizes)
    }

    private static func recordedWalk(
        _ target: (entry: WalkEntry, path: String),
        depth: Int,
        inodeSet: InodeSet,
        rootDevice: Int32,
        into sizes: inout [String: SizeResult]
    ) -> SizeAccumulator {
        let (entry, path) = target
        var accumulator = SizeAccumulator()
        defer { sizes[path] = accumulator.result() }

        guard !isForeignVolume(entry, rootDevice: rootDevice) else {
            if entry.kind == .directory {
                accumulator.addSkippedMount(path: path)
            }
            return accumulator
        }

        // A leaf as far as recording goes: one walk, one number.
        guard depth > 1, entry.kind == .directory, !AtomicBundles.isAtomicBundle(URL(fileURLWithPath: path)) else {
            walkInternal(entry: entry, path: path, inodeSet: inodeSet, accumulator: &accumulator, rootDevice: rootDevice)
            return accumulator
        }

        // Recorded as well as its children: the level above is still a row wherever a location lists at that level.
        let readable = DirectoryEntryReader.forEachEntry(inDirectory: path) { child in
            accumulator.merge(
                recordedWalk(
                    (child, DirectoryEntryReader.childPath(path, child.name)),
                    depth: depth - 1,
                    inodeSet: inodeSet,
                    rootDevice: rootDevice,
                    into: &sizes
                )
            )
        }
        if !readable {
            accumulator.addUnreadableDirectory(path: path)
        }
        return accumulator
    }

    private static func walkInternal(
        entry: WalkEntry,
        path: String,
        inodeSet: InodeSet,
        accumulator: inout SizeAccumulator,
        cutoff: Date? = nil,
        rootDevice: Int32
    ) {
        if let cutoff, entry.creationDate > cutoff {
            return
        }

        switch entry.kind {
        case .symlink:
            accumulator.addFile(allocatedBytes: entry.allocatedBytes, mtime: entry.modificationDate)
        case .regular:
            // Hardlink deduplication.
            if entry.linkCount > 1, !inodeSet.recordHardlinkIfFirstSeen(device: entry.device, inode: entry.inode) {
                return
            }
            accumulator.addFile(
                allocatedBytes: entry.allocatedBytes,
                exclusiveBytes: entry.exclusiveBytes,
                cloneFamily: entry.cloneFamily,
                mtime: entry.modificationDate
            )
        case .directory:
            walkChildren(ofDirectory: path, inodeSet: inodeSet, accumulator: &accumulator, cutoff: cutoff, rootDevice: rootDevice)
        case .other:
            return
        }
    }

    private static func walkChildren(
        ofDirectory path: String,
        inodeSet: InodeSet,
        accumulator: inout SizeAccumulator,
        cutoff: Date?,
        rootDevice: Int32
    ) {
        // Subdirectories are walked after this directory is closed, so open descriptors and buffers stay one deep.
        var subdirectories: [(entry: WalkEntry, path: String)] = []
        let readable = DirectoryEntryReader.forEachEntry(inDirectory: path, names: .directoriesOnly) { child in
            guard !isForeignVolume(child, rootDevice: rootDevice) else {
                if child.kind == .directory {
                    accumulator.addSkippedMount(path: DirectoryEntryReader.childPath(path, child.name))
                }
                return
            }
            if child.kind == .directory {
                subdirectories.append((child, DirectoryEntryReader.childPath(path, child.name)))
            } else {
                // A file never reads `path`; only a directory walks it.
                walkInternal(
                    entry: child,
                    path: path,
                    inodeSet: inodeSet,
                    accumulator: &accumulator,
                    cutoff: cutoff,
                    rootDevice: rootDevice
                )
            }
        }
        // A directory the app cannot open is not an empty directory.
        if !readable {
            accumulator.addUnreadableDirectory(path: path)
        }
        for subdirectory in subdirectories {
            walkInternal(
                entry: subdirectory.entry,
                path: subdirectory.path,
                inodeSet: inodeSet,
                accumulator: &accumulator,
                cutoff: cutoff,
                rootDevice: rootDevice
            )
        }
    }

    private static func isForeignVolume(_ entry: WalkEntry, rootDevice: Int32) -> Bool {
        entry.isMountPoint || entry.device != rootDevice
    }
}
