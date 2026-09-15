import Darwin
import Foundation

public enum FingerprintCheckResult: Sendable, Equatable {
    case valid
    case missing
    case pathChanged(expected: String, actual: String)
    case changedSinceScan(reason: String)
}

public struct Fingerprint: Sendable, Hashable {
    public let path: String
    public let modificationDate: Date
    public let inode: UInt64
    public let device: Int32
    public let isDirectory: Bool

    public init(
        path: String,
        modificationDate: Date,
        inode: UInt64,
        device: Int32,
        isDirectory: Bool
    ) {
        self.path = path
        self.modificationDate = modificationDate
        self.inode = inode
        self.device = device
        self.isDirectory = isDirectory
    }

    /// Captures the current fingerprint for a given URL, resolving symlinks.
    public static func capture(at url: URL) -> Fingerprint? {
        let path = PathNormalizer.normalize(url.path(percentEncoded: false))
        var statBuf = stat()
        guard lstat(path, &statBuf) == 0 else {
            return nil
        }

        let mtime = Date(
            timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec) +
                TimeInterval(statBuf.st_mtimespec.tv_nsec) / 1_000_000_000.0
        )
        let isDir = (statBuf.st_mode & S_IFMT) == S_IFDIR

        return Fingerprint(
            path: path,
            modificationDate: mtime,
            inode: UInt64(statBuf.st_ino),
            device: Int32(statBuf.st_dev),
            isDirectory: isDir
        )
    }

    /// Checks the target at `url` against this fingerprint immediately prior to deletion.
    public func verify(at url: URL) -> FingerprintCheckResult {
        let currentPath = PathNormalizer.normalize(url.path(percentEncoded: false))

        if currentPath != path {
            return .pathChanged(expected: path, actual: currentPath)
        }

        var statBuf = stat()
        guard lstat(currentPath, &statBuf) == 0 else {
            return .missing
        }

        let currentInode = UInt64(statBuf.st_ino)
        let currentDev = Int32(statBuf.st_dev)
        if currentInode != inode || currentDev != device {
            return .changedSinceScan(reason: "File inode or filesystem changed since scan")
        }

        let isDir = (statBuf.st_mode & S_IFMT) == S_IFDIR
        if isDir != isDirectory {
            return .changedSinceScan(reason: "changed since scan")
        }

        if !isDirectory {
            let currentMtime = Date(
                timeIntervalSince1970: TimeInterval(statBuf.st_mtimespec.tv_sec) +
                    TimeInterval(statBuf.st_mtimespec.tv_nsec) / 1_000_000_000.0
            )
            // Modified after capture, with 1ms tolerance for timestamp coarseness.
            if currentMtime.timeIntervalSince(modificationDate) > 0.001 {
                return .changedSinceScan(reason: "changed since scan")
            }
        }

        return .valid
    }
}
