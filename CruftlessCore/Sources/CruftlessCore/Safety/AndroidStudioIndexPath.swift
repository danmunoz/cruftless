import Darwin
import Foundation

/// Identifies the default versioned Android Studio index directory without granting deletion authority.
public enum AndroidStudioIndexPath {
    /// Returns the canonical path only when it is the exact default index directory for a recognized Studio install.
    public static func validate(
        _ candidate: URL,
        home: URL,
        protectedPaths: ProtectedPaths
    ) -> URL? {
        validate(candidate, home: home, protectedPaths: protectedPaths, deviceNumberReader: deviceNumber)
    }

    /// Returns an exact default version directory for validating app-owned pending records.
    public static func validateVersionDirectory(
        _ candidate: URL,
        home: URL,
        protectedPaths: ProtectedPaths
    ) -> URL? {
        guard candidate.isFileURL, home.isFileURL,
              candidate.host(percentEncoded: false)?.isEmpty != false,
              home.host(percentEncoded: false)?.isEmpty != false,
              !candidate.path(percentEncoded: false).split(separator: "/").contains(".."),
              !home.path(percentEncoded: false).split(separator: "/").contains("..")
        else { return nil }

        let homePath = ProtectedPaths.normalize(home)
        let candidatePath = ProtectedPaths.standardize(candidate)
        let prefix = homePath == "/" ? "/" : homePath + "/"
        guard candidatePath.hasPrefix(prefix) else { return nil }
        let relative = candidatePath.dropFirst(prefix.count).split(separator: "/").map(String.init)
        guard relative.count == 4,
              relative[0] == "Library",
              relative[1] == "Caches",
              relative[2] == "Google",
              RootResolver.isStudioDirectoryName(relative[3])
        else { return nil }

        let canonical = URL(fileURLWithPath: homePath, isDirectory: true)
            .appendingPathComponent(relative.joined(separator: "/"), isDirectory: true)
        guard ProtectedPaths.standardize(candidate) == ProtectedPaths.standardize(canonical),
              RootResolver.androidStudioSystemIssue(home: URL(fileURLWithPath: homePath, isDirectory: true)) == nil,
              !protectedPaths.intersectsCustomProtection(canonical),
              !protectedPaths.containsProtectedDescendant(in: canonical),
              hasSafeDirectoryChain(
                from: URL(fileURLWithPath: homePath, isDirectory: true),
                to: canonical,
                deviceNumberReader: deviceNumber
              )
        else { return nil }
        return canonical
    }

    static func validate(
        _ candidate: URL,
        home: URL,
        protectedPaths: ProtectedPaths,
        deviceNumberReader: (URL) -> UInt64?
    ) -> URL? {
        guard candidate.isFileURL, home.isFileURL,
              candidate.host(percentEncoded: false)?.isEmpty != false,
              home.host(percentEncoded: false)?.isEmpty != false,
              !candidate.path(percentEncoded: false).split(separator: "/").contains(".."),
              !home.path(percentEncoded: false).split(separator: "/").contains("..")
        else { return nil }

        guard let versionDirectory = validateVersionDirectory(
            candidate.deletingLastPathComponent(),
            home: home,
            protectedPaths: protectedPaths
        ), candidate.lastPathComponent == "index"
        else { return nil }

        let canonicalTarget = versionDirectory.appendingPathComponent("index", isDirectory: true)
        let canonicalHome = URL(fileURLWithPath: ProtectedPaths.normalize(home), isDirectory: true)
        guard ProtectedPaths.standardize(candidate) == ProtectedPaths.standardize(canonicalTarget),
              !protectedPaths.intersectsCustomProtection(canonicalTarget),
              !protectedPaths.containsProtectedDescendant(in: canonicalTarget),
              hasSafeDirectoryChain(
                from: canonicalHome,
                to: canonicalTarget,
                deviceNumberReader: deviceNumberReader
              )
        else { return nil }

        return canonicalTarget
    }

    private static func hasSafeDirectoryChain(
        from home: URL,
        to target: URL,
        deviceNumberReader: (URL) -> UInt64?
    ) -> Bool {
        guard isDirectoryWithoutFollowingLinks(home),
              let homeDevice = deviceNumberReader(home)
        else { return false }

        let homePath = ProtectedPaths.standardize(home)
        let targetPath = ProtectedPaths.standardize(target)
        let relative = targetPath.dropFirst(homePath.count)
        var currentPath = homePath
        for component in relative.split(separator: "/") {
            currentPath += "/" + component
            let current = URL(fileURLWithPath: currentPath)
            guard isDirectoryWithoutFollowingLinks(current),
                  deviceNumberReader(current) == homeDevice
            else { return false }
        }
        return true
    }

    private static func isDirectoryWithoutFollowingLinks(_ url: URL) -> Bool {
        var info = stat()
        return lstat(ProtectedPaths.standardize(url), &info) == 0
            && (info.st_mode & S_IFMT) == S_IFDIR
    }

    private static func deviceNumber(_ url: URL) -> UInt64? {
        var info = stat()
        guard lstat(ProtectedPaths.standardize(url), &info) == 0 else { return nil }
        return UInt64(info.st_dev)
    }
}
