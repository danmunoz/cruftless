import Darwin
import Foundation

public enum PathGuardError: Error, Sendable, Equatable {
    case outsideAllowlistedRoots(String)
    case matchesRootItself(String)
    case protectedPath(String)
    case emptyOrRelativePath(String)
    case notAnAllowlistedRoot(String)
    case rootHasProtectedDescendant(String)
    case containsProtectedDescendant(String)
    /// The final path component is a symlink.
    case symlinkTarget(String)
}

/// Validates target paths against allowlisted roots and protected path policies.
public struct PathGuard: Sendable {
    /// The roots this guard admits paths under.
    public let roots: [URL]

    public let protectedPaths: ProtectedPaths

    public init(roots: [URL], protectedPaths: ProtectedPaths = .default) {
        self.protectedPaths = protectedPaths
        self.roots = roots.filter { protectedPaths.isUsableRoot($0) }
    }

    /// Validates that a target URL is strictly inside one of the allowlisted roots and does not violate any protection rules.
    public func validate(_ target: URL) throws -> ValidatedPath {
        let rawPath = try Self.absolutePath(of: target)

        // Disallow path traversal components.
        if target.pathComponents.contains("..") {
            let normalized = target.standardizedFileURL
            if normalized.pathComponents.contains("..") {
                throw PathGuardError.emptyOrRelativePath(rawPath)
            }
        }

        // Check against protected paths first (denylist always wins).
        if protectedPaths.isProtected(target) {
            let resolved = ProtectedPaths.normalize(target)
            throw PathGuardError.protectedPath(resolved)
        }

        try Self.refuseSymlinkFinalComponent(target)

        let resolvedTargetPath = ProtectedPaths.normalize(target)
        let resolvedRoots = roots.map { ProtectedPaths.normalize($0) }

        if resolvedRoots.contains(resolvedTargetPath) {
            throw PathGuardError.matchesRootItself(resolvedTargetPath)
        }

        // The trailing slash enforces path-component boundaries.
        let matchedRoot = resolvedRoots.contains { resolvedTargetPath.hasPrefix($0 + "/") }
        guard matchedRoot else {
            throw PathGuardError.outsideAllowlistedRoots(resolvedTargetPath)
        }

        guard !protectedPaths.containsProtectedDescendant(in: target) else {
            throw PathGuardError.containsProtectedDescendant(resolvedTargetPath)
        }

        let resolvedURL = URL(fileURLWithPath: resolvedTargetPath, isDirectory: target.hasDirectoryPath)
        return ValidatedPath(
            validatedURL: resolvedURL,
            path: resolvedTargetPath,
            allowlistedRootPaths: resolvedRoots
        )
    }

    /// Validates one recognized Gradle cache directory without making Gradle User Home writable.
    package func validateGradleCacheEntry(_ target: URL) throws -> ValidatedPath {
        let rawPath = try Self.absolutePath(of: target)
        guard !target.pathComponents.contains("..") else {
            throw PathGuardError.emptyOrRelativePath(rawPath)
        }
        try Self.refuseSymlinkFinalComponent(target)

        let resolvedTargetPath = ProtectedPaths.normalize(target)
        for cacheRoot in RootResolver.gradleCacheRoots() {
            let rootPath = ProtectedPaths.normalize(cacheRoot)
            guard cacheRoot.lastPathComponent == "caches",
                  resolvedTargetPath.hasPrefix(rootPath + "/")
            else { continue }

            let entryName = String(resolvedTargetPath.dropFirst(rootPath.count + 1))
            guard !entryName.isEmpty,
                  !entryName.contains("/"),
                  entryName == target.lastPathComponent,
                  GradleCacheEntryPolicy.isRecognizedCacheEntryName(entryName)
            else { continue }

            var info = stat()
            var rootInfo = stat()
            guard lstat(resolvedTargetPath, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR,
                  stat(rootPath, &rootInfo) == 0,
                  info.st_dev == rootInfo.st_dev
            else { throw PathGuardError.protectedPath(resolvedTargetPath) }

            guard protectedPaths.allowsGradleCacheEntry(target, under: cacheRoot),
                  !protectedPaths.containsProtectedDescendant(in: target)
            else { throw PathGuardError.protectedPath(resolvedTargetPath) }

            return ValidatedPath(
                validatedURL: URL(fileURLWithPath: resolvedTargetPath, isDirectory: true),
                path: resolvedTargetPath,
                allowlistedRootPaths: [rootPath]
            )
        }
        throw PathGuardError.outsideAllowlistedRoots(resolvedTargetPath)
    }

    public func validateRoot(_ target: URL) throws -> ValidatedPath {
        _ = try Self.absolutePath(of: target)

        let resolvedTargetPath = ProtectedPaths.normalize(target)

        // Never the filesystem root, whatever the allowlist claims.
        guard resolvedTargetPath != "/" else {
            throw PathGuardError.protectedPath(resolvedTargetPath)
        }

        // Denylist still wins, exactly as in `validate(_:)`.
        if protectedPaths.isProtected(target) {
            throw PathGuardError.protectedPath(resolvedTargetPath)
        }

        try Self.refuseSymlinkFinalComponent(target)

        let matchesRoot = roots.contains { ProtectedPaths.normalize($0) == resolvedTargetPath }
        guard matchesRoot else {
            throw PathGuardError.notAnAllowlistedRoot(resolvedTargetPath)
        }

        guard !protectedPaths.containsProtectedDescendant(in: target) else {
            throw PathGuardError.rootHasProtectedDescendant(resolvedTargetPath)
        }

        let resolvedURL = URL(fileURLWithPath: resolvedTargetPath, isDirectory: true)
        return ValidatedPath(
            validatedURL: resolvedURL,
            path: resolvedTargetPath,
            isRoot: true,
            allowlistedRootPaths: roots.map(ProtectedPaths.normalize)
        )
    }

    /// The target must be an absolute file URL with no host.
    private static func absolutePath(of target: URL) throws -> String {
        let rawPath = target.path(percentEncoded: false)
        let host = target.host(percentEncoded: false) ?? ""
        guard !rawPath.isEmpty, target.isFileURL, host.isEmpty,
              rawPath.hasPrefix("/"), !rawPath.contains("\0") else {
            throw PathGuardError.emptyOrRelativePath(rawPath)
        }
        return rawPath
    }

    /// The guard never swaps a target for whatever a link points at.
    private static func refuseSymlinkFinalComponent(_ target: URL) throws {
        let lexicalPath = ProtectedPaths.standardize(target)
        if PathNormalizer.finalComponentIsSymlink(lexicalPath) {
            throw PathGuardError.symlinkTarget(lexicalPath)
        }
    }
}
