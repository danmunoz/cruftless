import Darwin
import Foundation

/// What a Derived Data folder's `info.plist` says about the project that produced it.
public enum DerivedDataWorkspace: Sendable, Hashable {
    /// The recorded workspace or project still exists.
    case live(String)
    /// The recorded workspace or project is gone from a reachable volume.
    case orphaned(String)
    /// No usable record, an unreachable volume, or an unanswerable check; never treated as orphaned.
    case unknown

    /// The recorded absolute workspace path, when there is one.
    public var path: String? {
        switch self {
        case let .live(path), let .orphaned(path): path
        case .unknown: nil
        }
    }

    public var isOrphaned: Bool {
        if case .orphaned = self { return true }
        return false
    }
}

/// Reads and classifies the `WorkspacePath` Xcode records in each Derived Data project folder.
public enum DerivedDataWorkspaceReader: Sendable {
    /// The file Xcode writes at the top of every per-project Derived Data folder.
    public static let infoPlistName = "info.plist"

    /// Whether the volume mounted at a `/Volumes/<name>` path is reachable.
    public typealias VolumeMountCheck = @Sendable (String) -> Bool

    /// Classifies one Derived Data child folder.
    public static func classify(
        folder: URL,
        isVolumeMounted: VolumeMountCheck = { isMountPoint($0) }
    ) -> DerivedDataWorkspace {
        guard let workspacePath = workspacePath(inFolder: folder) else { return .unknown }
        return classify(workspacePath: workspacePath, isVolumeMounted: isVolumeMounted)
    }

    /// Classifies a recorded workspace path.
    public static func classify(
        workspacePath: String,
        isVolumeMounted: VolumeMountCheck = { isMountPoint($0) }
    ) -> DerivedDataWorkspace {
        guard workspacePath.hasPrefix("/"), workspacePath != "/" else { return .unknown }
        if let volume = volumeMountPath(for: workspacePath), !isVolumeMounted(volume) {
            return .unknown
        }
        switch existence(of: workspacePath) {
        case .exists: return .live(workspacePath)
        case .missing: return .orphaned(workspacePath)
        case .undetermined: return .unknown
        }
    }

    /// Whether a folder still records exactly this missing workspace, read fresh from disk.
    public static func isStillOrphaned(
        folder: URL,
        workspacePath: String,
        isVolumeMounted: VolumeMountCheck = { isMountPoint($0) }
    ) -> Bool {
        classify(folder: folder, isVolumeMounted: isVolumeMounted) == .orphaned(workspacePath)
    }

    /// The `WorkspacePath` recorded in a Derived Data folder's `info.plist`, binary or XML.
    public static func workspacePath(inFolder folder: URL) -> String? {
        let plistURL = folder.appendingPathComponent(infoPlistName, isDirectory: false)
        guard let data = FileAccessAudit.data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let path = plist["WorkspacePath"] as? String,
              !path.isEmpty
        else { return nil }
        return path
    }

    /// The `/Volumes/<name>` prefix of a path on an external or network volume.
    static func volumeMountPath(for path: String) -> String? {
        let components = (path as NSString).standardizingPath.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2, components[0] == "Volumes" else { return nil }
        return "/Volumes/\(components[1])"
    }

    /// Whether a path is the mount point of a mounted file system, following a symlink such as the boot volume's.
    public static func isMountPoint(_ path: String) -> Bool {
        let resolved = URL(fileURLWithPath: path).resolvingSymlinksInPath().path(percentEncoded: false)
        var fileSystem = statfs()
        guard statfs(resolved, &fileSystem) == 0 else { return false }
        let mountedOn = withUnsafeBytes(of: fileSystem.f_mntonname) { buffer in
            String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
        }
        return mountedOn == resolved
    }

    private enum Existence {
        case exists, missing, undetermined
    }

    /// A missing path is one that neither `stat` nor `lstat` can find; any other failure leaves the answer open.
    private static func existence(of path: String) -> Existence {
        var info = stat()
        if stat(path, &info) == 0 { return .exists }
        guard errno == ENOENT || errno == ENOTDIR else { return .undetermined }
        return lstat(path, &info) == 0 ? .undetermined : .missing
    }
}
