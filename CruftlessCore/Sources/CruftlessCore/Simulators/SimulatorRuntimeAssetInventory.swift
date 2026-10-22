import Darwin
import Foundation

public enum SimulatorRuntimeAssetInventory: Sendable {
    public static let defaultRoot = URL(
        fileURLWithPath: "/System/Library/AssetsV2/com_apple_MobileAsset_iOSSimulatorRuntime",
        isDirectory: true
    )
    private static let measurementQueue = DispatchQueue(label: "com.cruftless.runtime-assets", qos: .utility)

    public static func sizeBytesAsync(version: String, build: String, root: URL = defaultRoot) async -> Int64? {
        await withCheckedContinuation { continuation in
            measurementQueue.async {
                continuation.resume(returning: sizeBytes(version: version, build: build, root: root))
            }
        }
    }

    public static func sizeBytes(version: String, build: String, root: URL = defaultRoot) -> Int64? {
        measure(version: version, build: build, root: root, inodeSet: InodeSet(), seenAssets: nil)
    }

    package static func sizesBytesAsync(for runtimes: [SimulatorRuntimeCatalog.Runtime], root: URL = defaultRoot) async -> [String: Int64] {
        await withCheckedContinuation { continuation in
            measurementQueue.async {
                continuation.resume(returning: sizesBytes(for: runtimes, root: root))
            }
        }
    }

    package static func sizesBytes(for runtimes: [SimulatorRuntimeCatalog.Runtime], root: URL = defaultRoot) -> [String: Int64] {
        let inodeSet = InodeSet()
        let seenAssets = InodeSet()
        var result: [String: Int64] = [:]
        for runtime in runtimes.sorted(by: { $0.id < $1.id }) where result[runtime.id] == nil {
            if let size = measure(version: runtime.version, build: runtime.build, root: root, inodeSet: inodeSet, seenAssets: seenAssets) {
                result[runtime.id] = size
            }
        }
        return result
    }

    private static func measure(version: String, build: String, root: URL, inodeSet: InodeSet, seenAssets: InodeSet?) -> Int64? {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        var rootStat = stat()
        guard lstat(rootPath, &rootStat) == 0, (rootStat.st_mode & S_IFMT) == S_IFDIR,
              !isSymlink(rootPath) else { return nil }
        guard let asset = matchingAsset(version: version, build: build, root: root) else { return nil }
        let assetData = asset.appendingPathComponent("AssetData", isDirectory: true)
        guard !isSymlink(assetData.path) else { return nil }
        var dataStat = stat()
        guard lstat(assetData.path, &dataStat) == 0,
              (dataStat.st_mode & S_IFMT) == S_IFDIR,
              dataStat.st_dev == rootStat.st_dev else { return nil }
        if let seenAssets,
           !seenAssets.recordHardlinkIfFirstSeen(device: Int32(dataStat.st_dev), inode: UInt64(dataStat.st_ino)) { return 0 }
        let measured = DirectoryWalker.walk(url: assetData, inodeSet: inodeSet)
        guard measured.unreadableDirectoryCount == 0, measured.skippedMountCount == 0 else { return nil }
        return measured.allocatedBytes
    }

    private static func matchingAsset(version: String, build: String, root: URL) -> URL? {
        let rootPath = root.standardizedFileURL.path(percentEncoded: false)
        guard let dir = opendir(rootPath) else { return nil }
        defer { closedir(dir) }
        var matches: [URL] = []
        var count = 0
        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry), name.hasSuffix(".asset") else { continue }
            count += 1
            guard count <= 512 else { return nil }
            let asset = root.appendingPathComponent(name, isDirectory: true)
            let info = asset.appendingPathComponent("Info.plist")
            guard !isSymlink(asset.path), !isSymlink(info.path) else { continue }
            guard let data = RootResolver.boundedSDKMetadata(at: info, maximumBytes: 65536),
                  let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
                  let properties = plist["MobileAssetProperties"] as? [String: Any],
                  properties["Build"] as? String == build,
                  properties["SimulatorVersion"] as? String == version else { continue }
            matches.append(asset)
            if matches.count > 1 { return nil }
        }
        return matches.count == 1 ? matches.first : nil
    }

    private static func isSymlink(_ path: String) -> Bool {
        var value = stat()
        return lstat(path, &value) == 0 && (value.st_mode & S_IFMT) == S_IFLNK
    }
}
