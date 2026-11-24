import Darwin
import Foundation

public struct SizeResult: Sendable, Hashable {
    public let allocatedBytes: Int64
    /// Bytes deleting this tree alone would free: allocated space minus blocks shared with APFS clones outside it.
    public let exclusiveBytes: Int64
    public let newestMtime: Date?

    /// Directories the walk could not open: a permission-denied `opendir` under a root the app is otherwise allowed to read.
    public let unreadableDirectoryCount: Int
    /// The first directory the walk could not open, for the message the list shows.
    public let firstUnreadablePath: String?
    /// Directories skipped because they are mounted on another volume.
    public let skippedMountCount: Int
    /// The first nested volume skipped by the walk.
    public let firstSkippedMountPath: String?

    public init(
        allocatedBytes: Int64,
        exclusiveBytes: Int64? = nil,
        newestMtime: Date?,
        unreadableDirectoryCount: Int = 0,
        firstUnreadablePath: String? = nil,
        skippedMountCount: Int = 0,
        firstSkippedMountPath: String? = nil
    ) {
        self.allocatedBytes = allocatedBytes
        self.exclusiveBytes = exclusiveBytes ?? allocatedBytes
        self.newestMtime = newestMtime
        self.unreadableDirectoryCount = unreadableDirectoryCount
        self.firstUnreadablePath = firstUnreadablePath
        self.skippedMountCount = skippedMountCount
        self.firstSkippedMountPath = firstSkippedMountPath
    }

    public static let zero = SizeResult(allocatedBytes: 0, newestMtime: nil)
}

/// Accumulates allocated file sizes (APFS allocated space) and tracks highest modification timestamps.
public struct SizeAccumulator: Sendable {
    private var allocated: Int64 = 0
    private var exclusive: Int64 = 0
    private var clones = CloneTally()
    private var latestMtime: Date?
    private var unreadableDirectories: Int = 0
    private var firstUnreadable: String?
    private var skippedMounts: Int = 0
    private var firstSkippedMount: String?

    public init() {}

    public mutating func addFile(allocatedBytes: Int64, mtime: Date) {
        addFile(allocatedBytes: allocatedBytes, exclusiveBytes: allocatedBytes, cloneFamily: nil, mtime: mtime)
    }

    mutating func addFile(allocatedBytes: Int64, exclusiveBytes: Int64, cloneFamily: CloneFamilyMember?, mtime: Date) {
        allocated += allocatedBytes
        exclusive += exclusiveBytes
        if let cloneFamily {
            clones.record(cloneFamily)
        }
        if let current = latestMtime {
            if mtime > current {
                latestMtime = mtime
            }
        } else {
            latestMtime = mtime
        }
    }

    /// Records a directory the walk could not descend into.
    public mutating func addUnreadableDirectory(path: String) {
        unreadableDirectories += 1
        if firstUnreadable == nil {
            firstUnreadable = path
        }
    }

    /// Records a nested volume the walk intentionally skipped.
    public mutating func addSkippedMount(path: String) {
        skippedMounts += 1
        if firstSkippedMount == nil {
            firstSkippedMount = path
        }
    }

    /// Adds a finished result; clone families it left incomplete stay uncounted.
    public mutating func add(_ result: SizeResult) {
        allocated += result.allocatedBytes
        exclusive += result.exclusiveBytes
        unreadableDirectories += result.unreadableDirectoryCount
        if firstUnreadable == nil {
            firstUnreadable = result.firstUnreadablePath
        }
        skippedMounts += result.skippedMountCount
        if firstSkippedMount == nil {
            firstSkippedMount = result.firstSkippedMountPath
        }
        if let mtime = result.newestMtime {
            if let current = latestMtime {
                if mtime > current { latestMtime = mtime }
            } else {
                latestMtime = mtime
            }
        }
    }

    /// Adds a sibling subtree, completing clone families split across the two.
    mutating func merge(_ other: SizeAccumulator) {
        clones.merge(other.clones)
        add(SizeResult(allocatedBytes: other.allocated, exclusiveBytes: other.exclusive, newestMtime: other.latestMtime))
        unreadableDirectories += other.unreadableDirectories
        if firstUnreadable == nil {
            firstUnreadable = other.firstUnreadable
        }
        skippedMounts += other.skippedMounts
        if firstSkippedMount == nil {
            firstSkippedMount = other.firstSkippedMount
        }
    }

    public func result() -> SizeResult {
        SizeResult(
            allocatedBytes: allocated,
            exclusiveBytes: exclusive + clones.completedSharedBytes,
            newestMtime: latestMtime,
            unreadableDirectoryCount: unreadableDirectories,
            firstUnreadablePath: firstUnreadable,
            skippedMountCount: skippedMounts,
            firstSkippedMountPath: firstSkippedMount
        )
    }
}
