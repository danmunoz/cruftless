import Darwin
import Foundation

public struct SizeResult: Sendable, Hashable {
    public let allocatedBytes: Int64
    public let newestMtime: Date?

    /// Directories the walk could not open: a permission-denied `opendir` under a root the app is otherwise allowed to read.
    public let unreadableDirectoryCount: Int
    /// The first directory the walk could not open, for the message the list shows.
    public let firstUnreadablePath: String?

    public init(
        allocatedBytes: Int64,
        newestMtime: Date?,
        unreadableDirectoryCount: Int = 0,
        firstUnreadablePath: String? = nil
    ) {
        self.allocatedBytes = allocatedBytes
        self.newestMtime = newestMtime
        self.unreadableDirectoryCount = unreadableDirectoryCount
        self.firstUnreadablePath = firstUnreadablePath
    }

    public static let zero = SizeResult(allocatedBytes: 0, newestMtime: nil)
}

/// Accumulates allocated file sizes (APFS allocated space) and tracks highest modification timestamps.
public struct SizeAccumulator: Sendable {
    private var allocated: Int64 = 0
    private var latestMtime: Date?
    private var unreadableDirectories: Int = 0
    private var firstUnreadable: String?

    public init() {}

    public mutating func addFile(allocatedBytes: Int64, mtime: Date) {
        allocated += allocatedBytes
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

    public mutating func add(_ result: SizeResult) {
        allocated += result.allocatedBytes
        unreadableDirectories += result.unreadableDirectoryCount
        if firstUnreadable == nil {
            firstUnreadable = result.firstUnreadablePath
        }
        if let mtime = result.newestMtime {
            if let current = latestMtime {
                if mtime > current { latestMtime = mtime }
            } else {
                latestMtime = mtime
            }
        }
    }

    public func result() -> SizeResult {
        SizeResult(
            allocatedBytes: allocated,
            newestMtime: latestMtime,
            unreadableDirectoryCount: unreadableDirectories,
            firstUnreadablePath: firstUnreadable
        )
    }
}
