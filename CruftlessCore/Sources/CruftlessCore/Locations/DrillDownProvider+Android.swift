import Darwin
import Foundation

extension DrillDownProvider {
    static func androidSDKPackages(
        in roots: [URL],
        rootSizes: [RootSize] = [],
        knownSizes: [String: [String: SizeResult]] = [:]
    ) -> (children: [ChildEntry], issue: String?) {
        var discovery = SDKPackageDiscovery(knownSizes: knownSizes)
        discovery.scan(roots)
        let packages = discovery.packages.values.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        var children = packages
        let measuredTotal = rootSizes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let classifiedTotal = children.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        let unclassifiedBytes = max(0, measuredTotal - classifiedTotal)
        children.append(unclassifiedEntry(
            id: "androidSDK-unclassified",
            name: "Unclassified SDK contents",
            bytes: unclassifiedBytes,
            root: roots.first,
            consequence: "Read-only Android SDK data that is not classified as a package."
        ))
        return (
            children.filter { $0.reclaimableBytes > 0 }.sorted { $0.reclaimableBytes > $1.reclaimableBytes },
            discovery.issue
        )
    }

    static func androidAVDs(
        in roots: [URL],
        rootSizes: [RootSize] = [],
        knownSizes: [String: [String: SizeResult]] = [:]
    ) -> [ChildEntry] {
        let devices = RootResolver.androidAVDInventory(roots: roots)
        let inodeSet = InodeSet()
        var measuredDirectories: Set<String> = []
        var children = devices.map { device in
            var statBuf = stat()
            let path = ProtectedPaths.normalize(device.directory)
            let mtime = lstat(path, &statBuf) == 0 ? statBuf.st_mtimespec : timespec()
            let image = device.systemImage.map { " · \($0)" } ?? ""
            let measured = knownSizes.values.compactMap { $0[path]?.allocatedBytes }.first
                ?? rootSizes.first(where: { ProtectedPaths.normalize($0.url) == path })?.allocatedBytes
                ?? DirectoryWalker.walk(url: device.directory, inodeSet: inodeSet).allocatedBytes
            let size = measuredDirectories.insert(path).inserted ? measured : 0
            return ChildEntry(
                id: "androidAVDs-\(device.registryPath)",
                name: "\(device.displayName) · \(device.registryName)\(image)",
                url: device.directory,
                reclaimableBytes: size,
                staleness: calculateStaleness(url: device.directory, source: .newestChildMtime, statMtime: mtime),
                tier: .info,
                consequence: "Read-only Android Virtual Device. Its apps, settings, snapshots and disk images are user data."
            )
        }.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
        let measuredTotal = rootSizes.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        let classifiedTotal = children.reduce(Int64(0)) { $0 + $1.reclaimableBytes }
        let remainder = max(0, measuredTotal - classifiedTotal)
        if remainder > 0 {
        children.append(ChildEntry(
                id: "androidAVDs-unclassified",
                name: "Unclassified AVD contents",
                url: roots.first ?? URL(fileURLWithPath: "/"),
                reclaimableBytes: remainder,
                staleness: StalenessInfo(lastUsedDate: nil),
                tier: .info,
                consequence: "Read-only AVD registry and unclassified contents."
            ))
        }
        return children
    }

    fileprivate static func packageEntry(
        _ package: AndroidSDKPackage,
        at url: URL,
        inodeSet: InodeSet,
        knownSizes: [String: SizeResult]
    ) -> ChildEntry {
        let path = ProtectedPaths.normalize(url)
        var statBuf = stat()
        let mtime = lstat(path, &statBuf) == 0 ? statBuf.st_mtimespec : timespec()
        let revision = package.revision.map { " · \($0)" } ?? ""
        let identity = package.packagePath.map { " (\($0))" } ?? ""
        return ChildEntry(
            id: "androidSDK-\(path)",
            name: "\(package.displayName)\(revision)\(identity)",
            url: url,
            reclaimableBytes: knownSizes[path]?.allocatedBytes ?? DirectoryWalker.walk(url: url, inodeSet: inodeSet).allocatedBytes,
            staleness: calculateStaleness(url: url, source: .newestChildMtime, statMtime: mtime),
            tier: .info,
            consequence: "Read-only installed Android SDK package."
        )
    }

    private static func unclassifiedEntry(id: String, name: String, bytes: Int64, root: URL?, consequence: String) -> ChildEntry {
        ChildEntry(
            id: id,
            name: name,
            url: root ?? URL(fileURLWithPath: "/"),
            reclaimableBytes: bytes,
            staleness: StalenessInfo(lastUsedDate: nil),
            tier: .info,
            consequence: consequence
        )
    }

}

private struct SDKPackageDiscovery {
    private let knownSizes: [String: [String: SizeResult]]
    private let inodeSet = InodeSet()
    private var visited = 0
    private var discovered = 0
    private var examinedEntries = 0
    private(set) var packages: [String: ChildEntry] = [:]
    private(set) var issue: String?

    init(knownSizes: [String: [String: SizeResult]]) {
        self.knownSizes = knownSizes
    }

    mutating func scan(_ roots: [URL]) {
        for root in roots { scan(root) }
    }

    private mutating func scan(_ root: URL) {
        var rootStat = stat()
        guard lstat(ProtectedPaths.normalize(root), &rootStat) == 0 else { return }
        if hasUnsupportedTopLevelEntries(in: root) {
            issue = "Some SDK contents are outside the supported package layouts. Inventory is incomplete."
        }
        let candidates = packageDirectories(in: root, rootDevice: UInt64(rootStat.st_dev))
        for candidate in candidates {
            visited += 1
            guard visited <= 4096 else {
                issue = "SDK package discovery reached its bounded directory or entry limit. Inventory is incomplete."
                return
            }
            guard let package = RootResolver.androidSDKPackage(at: candidate, sdkRoot: root) else {
                if hasPackageMetadata(candidate) {
                    issue = "Some SDK package metadata is malformed or does not match its layout. Inventory is incomplete."
                }
                continue
            }
            let path = ProtectedPaths.normalize(candidate)
            packages[path] = DrillDownProvider.packageEntry(
                package,
                at: candidate,
                inodeSet: inodeSet,
                knownSizes: knownSizes[ProtectedPaths.normalize(root)] ?? [:]
            )
        }
    }

    private func hasPackageMetadata(_ directory: URL) -> Bool {
        ["package.xml", "source.properties"].contains { name in
            var metadataStat = stat()
            return lstat(directory.appendingPathComponent(name).path(percentEncoded: false), &metadataStat) == 0
        }
    }

    private mutating func hasUnsupportedTopLevelEntries(in root: URL) -> Bool {
        let knownEntries: Set<String> = [
            "platform-tools", "emulator", "platforms", "build-tools", "sources", "system-images",
            "ndk", "cmake", "cmdline-tools", "extras", "licenses", "skins", "fonts",
            ".downloadIntermediates", ".knownPackages", ".temp", "tools", "add-ons", "patcher"
        ]
        guard let directory = opendir(ProtectedPaths.normalize(root)) else { return false }
        defer { closedir(directory) }
        var entries = 0
        while let entry = readdir(directory) {
            entries += 1
            guard entries <= 16_384 else {
                issue = "SDK package discovery reached its bounded directory or entry limit. Inventory is incomplete."
                return false
            }
            guard let name = Dirent.name(of: entry), name != ".", name != ".." else { continue }
            if !knownEntries.contains(name) { return true }
        }
        return false
    }

    private mutating func packageDirectories(in root: URL, rootDevice: UInt64) -> [URL] {
        let topLevel = childDirectories(of: root, rootDevice: rootDevice)
        var result: [URL] = []
        for directory in topLevel {
            let name = directory.lastPathComponent
            if name == "platform-tools" || name == "emulator" {
                result.append(directory)
            } else if ["platforms", "build-tools", "sources", "ndk", "cmake", "cmdline-tools"].contains(name) {
                result.append(contentsOf: childDirectories(of: directory, rootDevice: rootDevice))
            } else if name == "system-images" {
                for api in childDirectories(of: directory, rootDevice: rootDevice) {
                    for tag in childDirectories(of: api, rootDevice: rootDevice) {
                        result.append(contentsOf: childDirectories(of: tag, rootDevice: rootDevice))
                    }
                }
            } else if name == "extras" {
                for vendor in childDirectories(of: directory, rootDevice: rootDevice) {
                    result.append(contentsOf: childDirectories(of: vendor, rootDevice: rootDevice))
                }
            }
        }
        return result.filter { RootResolver.sdkPackagePath(for: $0, sdkRoot: root) != nil }
    }

    private mutating func childDirectories(of parent: URL, rootDevice: UInt64) -> [URL] {
        guard let directory = opendir(ProtectedPaths.normalize(parent)) else { return [] }
        defer { closedir(directory) }
        var result: [URL] = []
        while let entry = readdir(directory) {
            guard examinedEntries < 16_384 else {
                issue = "SDK package discovery reached its bounded directory or entry limit. Inventory is incomplete."
                return result
            }
            examinedEntries += 1
            guard let name = Dirent.name(of: entry), name != ".", name != ".." else { continue }
            let child = parent.appendingPathComponent(name, isDirectory: true)
            var childStat = stat()
            guard lstat(ProtectedPaths.normalize(child), &childStat) == 0,
                  (childStat.st_mode & S_IFMT) == S_IFDIR,
                  UInt64(childStat.st_dev) == rootDevice
            else { continue }
            discovered += 1
            guard discovered <= 4096 else {
                issue = "SDK package discovery reached its bounded directory or entry limit. Inventory is incomplete."
                return result
            }
            result.append(child)
        }
        return result
    }
}
