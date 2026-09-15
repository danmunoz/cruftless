import Darwin
import Foundation

/// Finds `.xcarchive` creation dates in the layout Xcode actually writes: `Archives/<date folder>/<App>.xcarchive`.
public enum ArchiveDates: Sendable {
    public static func newestCreationDate(under root: URL) -> Date? {
        var newest: Date?

        func consider(_ date: Date?) {
            guard let date else { return }
            if let current = newest {
                if date > current { newest = date }
            } else {
                newest = date
            }
        }

        for child in directChildren(of: root) {
            if child.name.hasSuffix(".xcarchive") {
                consider(DrillDownProvider.readArchiveCreationDate(at: child.url).lastUsedDate)
            } else if child.isDirectory {
                for nested in directChildren(of: child.url) where nested.name.hasSuffix(".xcarchive") {
                    consider(DrillDownProvider.readArchiveCreationDate(at: nested.url).lastUsedDate)
                }
            }
        }

        return newest
    }

    private struct DirectChild {
        let name: String
        let url: URL
        let isDirectory: Bool
    }

    /// Immediate, non-symlink children of `url`.
    private static func directChildren(of url: URL) -> [DirectChild] {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var results: [DirectChild] = []
        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }
            if name == "." || name == ".." { continue }

            var statBuf = stat()
            let childPath = (path as NSString).appendingPathComponent(name)
            guard lstat(childPath, &statBuf) == 0, (statBuf.st_mode & S_IFMT) != S_IFLNK else { continue }

            results.append(
                DirectChild(
                    name: name,
                    url: url.appendingPathComponent(name),
                    isDirectory: (statBuf.st_mode & S_IFMT) == S_IFDIR
                )
            )
        }
        return results
    }
}
