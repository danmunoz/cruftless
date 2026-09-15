import Darwin
import Foundation

/// Deterministic path normalization for the safety layer.
package enum PathNormalizer {
    package static func lexical(_ rawPath: String) -> String {
        let expanded = (rawPath as NSString).expandingTildeInPath
        let isAbsolute = expanded.hasPrefix("/")
        var stack: [String] = []
        for component in expanded.split(separator: "/", omittingEmptySubsequences: true) {
            switch component {
            case ".":
                continue
            case "..":
                if let last = stack.last, last != ".." {
                    stack.removeLast()
                } else if !isAbsolute {
                    // A relative path keeps a leading `..`; an absolute one cannot climb above `/`, so it is simply dropped.
                    stack.append("..")
                }
            default:
                stack.append(String(component))
            }
        }
        let joined = stack.joined(separator: "/")
        return isAbsolute ? "/" + joined : joined
    }

    package static func normalize(_ rawPath: String) -> String {
        let lexicalPath = lexical(rawPath)
        // An embedded NUL truncates the C string `realpath` sees, so the path resolved would not be the path checked.
        guard lexicalPath.hasPrefix("/"), !lexicalPath.contains("\0") else {
            return lexicalPath
        }

        var components = lexicalPath.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        var remainder: [String] = []
        while true {
            let candidate = components.isEmpty ? "/" : "/" + components.joined(separator: "/")
            if let resolved = realPath(of: candidate) {
                return join(base: resolved, remainder: remainder)
            }
            guard let last = components.popLast() else {
                return join(base: "/", remainder: remainder)
            }
            remainder.insert(last, at: 0)
        }
    }

    /// True when the *final* component of `path` is itself a symbolic link.
    package static func finalComponentIsSymlink(_ path: String) -> Bool {
        guard !path.isEmpty, !path.contains("\0") else { return false }
        var info = stat()
        guard lstat(path, &info) == 0 else { return false }
        return (info.st_mode & S_IFMT) == S_IFLNK
    }

    private static func join(base: String, remainder: [String]) -> String {
        let trimmedBase = stripTrailingSlash(base)
        guard !remainder.isEmpty else { return trimmedBase }
        let prefix = trimmedBase == "/" ? "" : trimmedBase
        return prefix + "/" + remainder.joined(separator: "/")
    }

    private static func stripTrailingSlash(_ path: String) -> String {
        var result = path
        while result.count > 1, result.hasSuffix("/") {
            result.removeLast()
        }
        return result
    }

    private static func realPath(of path: String) -> String? {
        guard let buffer = realpath(path, nil) else { return nil }
        defer { free(buffer) }
        return String(cString: buffer)
    }
}

/// The two spellings one path can have, both lowercased: as written (lexically standardized) and with symlinks resolved.
struct ProtectedPathForms: Sendable, Hashable {
    let lexical: String
    let resolved: String

    init(path: String) {
        lexical = PathNormalizer.lexical(path).lowercased()
        resolved = PathNormalizer.normalize(path).lowercased()
    }

    init(url: URL) {
        self.init(path: url.path(percentEncoded: false))
    }

    var variants: [String] {
        lexical == resolved ? [lexical] : [lexical, resolved]
    }

    /// True when `other` is this path or anything inside it.
    func coversOrEquals(_ other: ProtectedPathForms) -> Bool {
        matches(other) { mine, theirs in
            theirs == mine || theirs.hasPrefix(mine == "/" ? "/" : mine + "/")
        }
    }

    /// True when `other` is *strictly* inside this path.
    func strictlyContains(_ other: ProtectedPathForms) -> Bool {
        matches(other) { mine, theirs in
            theirs.hasPrefix(mine == "/" ? "/" : mine + "/")
        }
    }

    private func matches(_ other: ProtectedPathForms, _ predicate: (String, String) -> Bool) -> Bool {
        for mine in variants {
            for theirs in other.variants where predicate(mine, theirs) {
                return true
            }
        }
        return false
    }
}
