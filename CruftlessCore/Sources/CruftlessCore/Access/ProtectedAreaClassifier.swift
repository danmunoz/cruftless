import Darwin
import Foundation

/// Names the protected area a path lies in, using metadata calls only.
public struct ProtectedAreaClassifier: Sendable {
    /// The file system a path lives on, as `statfs` reports it.
    public struct Volume: Sendable, Hashable {
        public let mountPoint: String
        public let isLocal: Bool

        public init(mountPoint: String, isLocal: Bool) {
            self.mountPoint = mountPoint
            self.isLocal = isLocal
        }
    }

    /// Reports the volume holding a path, or `nil` when nothing can be inspected.
    public typealias VolumeInspector = @Sendable (String) -> Volume?

    private static let homeAreas: [(relativePath: String, area: ProtectedArea)] = [
        ("Documents", .documents),
        ("Desktop", .desktop),
        ("Downloads", .downloads),
        ("Library/Mobile Documents", .fileProvider),
        ("Library/CloudStorage", .fileProvider)
    ]

    private let homeSpellings: [String]
    private let inspectVolume: VolumeInspector

    public init(home: URL, inspectVolume: @escaping VolumeInspector = ProtectedAreaClassifier.statfsVolume) {
        let raw = home.path(percentEncoded: false)
        homeSpellings = Array(Set([PathNormalizer.lexical(raw), PathNormalizer.normalize(raw)].map { $0.lowercased() }))
        self.inspectVolume = inspectVolume
    }

    /// The classifier for the current user's home and the real mounted volumes.
    public static let standard = ProtectedAreaClassifier(home: RootResolver.homeURL)

    public func area(for url: URL) -> ProtectedArea? {
        area(forPath: url.path(percentEncoded: false))
    }

    /// The area `path` lies in, checked as written and with symlinks resolved.
    public func area(forPath path: String) -> ProtectedArea? {
        areaRoot(forPath: path)?.area
    }

    /// The folder whose first open raises the area's alert, together with the area.
    public func areaRoot(forPath path: String) -> (area: ProtectedArea, root: String)? {
        let lexical = PathNormalizer.lexical(path)
        guard lexical.hasPrefix("/"), !lexical.contains("\0") else { return nil }
        let resolved = PathNormalizer.normalize(lexical)
        let spellings = lexical == resolved ? [lexical] : [lexical, resolved]

        for spelling in spellings {
            if let match = homeArea(for: spelling) { return match }
        }
        for spelling in [resolved, lexical] {
            if let match = volumeArea(for: spelling) { return match }
        }
        return nil
    }

    private func homeArea(for spelling: String) -> (area: ProtectedArea, root: String)? {
        let lowered = spelling.lowercased()
        for home in homeSpellings {
            for (relativePath, area) in Self.homeAreas {
                let root = (home as NSString).appendingPathComponent(relativePath.lowercased())
                if lowered == root || lowered.hasPrefix(root + "/") {
                    let original = String(spelling.prefix(root.count))
                    return (area, original)
                }
            }
        }
        return nil
    }

    private func volumeArea(for spelling: String) -> (area: ProtectedArea, root: String)? {
        let components = spelling.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2, components[0] == "Volumes" else { return nil }
        let volumeRoot = "/Volumes/\(components[1])"
        guard let volume = inspectVolume(spelling) else { return nil }
        guard !Self.isBootVolume(volume.mountPoint) else { return nil }
        return (volume.isLocal ? .removableVolume : .networkVolume, volumeRoot)
    }

    private static func isBootVolume(_ mountPoint: String) -> Bool {
        mountPoint == "/" || mountPoint.hasPrefix("/System/Volumes/")
    }

    /// `statfs` on the longest existing prefix of `path`; it never opens the path.
    public static func statfsVolume(_ path: String) -> Volume? {
        var candidate = path
        while !candidate.isEmpty {
            var fileSystem = statfs()
            if statfs(candidate, &fileSystem) == 0 {
                let mountPoint = withUnsafeBytes(of: fileSystem.f_mntonname) { buffer in
                    String(bytes: buffer.prefix { $0 != 0 }, encoding: .utf8)
                } ?? candidate
                return Volume(mountPoint: mountPoint, isLocal: fileSystem.f_flags & UInt32(MNT_LOCAL) != 0)
            }
            guard candidate != "/" else { return nil }
            candidate = (candidate as NSString).deletingLastPathComponent
        }
        return nil
    }
}
