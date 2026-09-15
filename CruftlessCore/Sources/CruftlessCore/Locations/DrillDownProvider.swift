import Darwin
import Foundation

/// Resolves child entries lazily when the user navigates into a drill-down detail view.
public enum DrillDownProvider: Sendable {
    public static func sizeRecordingDepth(for location: TrackedLocation) -> Int {
        location.id == archivesLocationId ? 2 : 1
    }

    private static let archivesLocationId = "archives"

    public static func loadChildren(
        for location: TrackedLocation,
        knownSizes: [String: [String: SizeResult]] = [:]
    ) -> [ChildEntry] {
        let roots = location.resolveRoots()
        let inodeSet = InodeSet()
        var children: [ChildEntry] = []

        for root in roots {
            // A root that is itself a bundle is the leaf: the Xcode installs screen lists the installs, not the innards of Xcode.app.
            if AtomicBundles.isAtomicBundle(root) {
                children.append(
                    bundleRootEntry(
                        root: root,
                        location: location,
                        inodeSet: inodeSet,
                        knownSizes: knownSizes[ProtectedPaths.normalize(root)] ?? [:]
                    )
                )
                continue
            }

            children.append(
                contentsOf: entries(
                    in: root,
                    location: location,
                    inodeSet: inodeSet,
                    knownSizes: knownSizes[ProtectedPaths.normalize(root)] ?? [:]
                )
            )
        }

        return children.sorted { $0.reclaimableBytes > $1.reclaimableBytes }
    }

    /// Lists one root's immediate children, resolving each one's size.
    private static func entries(
        in root: URL,
        location: TrackedLocation,
        inodeSet: InodeSet,
        knownSizes sizesForRoot: [String: SizeResult]
    ) -> [ChildEntry] {
        let path = ProtectedPaths.normalize(root)
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var children: [ChildEntry] = []
        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }

            // Only "." and ".." are skipped; dotfiles are listed.
            if name == "." || name == ".." {
                continue
            }

            let childURL = root.appendingPathComponent(name)
            let childPath = (path as NSString).appendingPathComponent(name)

            var statBuf = stat()
            guard lstat(childPath, &statBuf) == 0 else { continue }

            // A symlink is never a row.
            guard (statBuf.st_mode & S_IFMT) != S_IFLNK else { continue }

            // For archives, look inside date folders if needed.
            if location.id == archivesLocationId, (statBuf.st_mode & S_IFMT) == S_IFDIR, !name.hasSuffix(".xcarchive") {
                let subArchives = loadArchives(
                    inDateFolder: childURL,
                    dateFolderPath: childPath,
                    locationID: location.id,
                    inodeSet: inodeSet,
                    knownSizes: sizesForRoot
                )
                children.append(contentsOf: subArchives)
                continue
            }

            let sizeResult = sizesForRoot[childPath] ?? DirectoryWalker.walk(url: childURL, inodeSet: inodeSet)
            let staleness = calculateStaleness(url: childURL, source: location.stalenessSource, statMtime: statBuf.st_mtimespec)

            let consequence = defaultConsequence(tier: location.tier, name: name)

            children.append(
                ChildEntry(
                    // Keyed by resolved path, not by name.
                    id: "\(location.id)-\(ProtectedPaths.normalize(childURL))",
                    name: name,
                    url: childURL,
                    reclaimableBytes: sizeResult.allocatedBytes,
                    staleness: staleness,
                    tier: location.tier,
                    consequence: consequence
                )
            )
        }

        return children
    }

    /// A root that is a bundle becomes a single entry naming the bundle itself.
    private static func bundleRootEntry(
        root: URL,
        location: TrackedLocation,
        inodeSet: InodeSet,
        knownSizes sizesForRoot: [String: SizeResult] = [:]
    ) -> ChildEntry {
        let size = sizesForRoot[ProtectedPaths.normalize(root)]
            ?? DirectoryWalker.walk(url: root, inodeSet: inodeSet)
        var statBuf = stat()
        let mtime = lstat(root.path(percentEncoded: false), &statBuf) == 0
            ? statBuf.st_mtimespec
            : timespec()

        return ChildEntry(
            id: "\(location.id)-\(ProtectedPaths.normalize(root))",
            name: root.lastPathComponent,
            url: root,
            reclaimableBytes: size.allocatedBytes,
            staleness: calculateStaleness(url: root, source: location.stalenessSource, statMtime: mtime),
            tier: location.tier,
            consequence: defaultConsequence(tier: location.tier, name: root.lastPathComponent)
        )
    }

    private static func loadArchives(
        inDateFolder dateURL: URL,
        dateFolderPath: String,
        locationID: String,
        inodeSet: InodeSet,
        knownSizes sizesForRoot: [String: SizeResult]
    ) -> [ChildEntry] {
        let path = dateFolderPath
        guard let dir = opendir(path) else { return [] }
        defer { closedir(dir) }

        var results: [ChildEntry] = []
        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }

            if name.hasSuffix(".xcarchive") {
                let archiveURL = dateURL.appendingPathComponent(name)

                // Skips symlink entries.
                var statBuf = stat()
                let archivePath = (path as NSString).appendingPathComponent(name)
                guard lstat(archivePath, &statBuf) == 0, (statBuf.st_mode & S_IFMT) != S_IFLNK else { continue }

                let sizeResult = sizesForRoot[archivePath]
                    ?? DirectoryWalker.walk(url: archiveURL, inodeSet: inodeSet)
                let staleness = readArchiveCreationDate(at: archiveURL)

                results.append(
                    ChildEntry(
                        id: "\(locationID)-\(ProtectedPaths.normalize(archiveURL))",
                        name: name,
                        url: archiveURL,
                        reclaimableBytes: sizeResult.allocatedBytes,
                        staleness: staleness,
                        tier: .irreversible,
                        consequence: "Deletes the dSYMs for this build. Crash reports from it can never be symbolicated again."
                    )
                )
            }
        }
        return results
    }

    public static func calculateStaleness(
        url: URL,
        source: StalenessSource,
        statMtime: timespec
    ) -> StalenessInfo {
        Staleness.resolve(
            source: source,
            archiveCreationDate: readArchiveCreationDate(at: url).lastUsedDate,
            simulatorLastUsedAt: simulatorLastUsedAt(deviceDirectory: url, fallbackMtime: statMtime),
            newestChildMtime: newestChildMtime(at: url) ?? date(from: statMtime),
            topLevelMtime: date(from: statMtime)
        )
    }

    private static func date(from mtimespec: timespec) -> Date {
        Date(timeIntervalSince1970: TimeInterval(mtimespec.tv_sec) + TimeInterval(mtimespec.tv_nsec) / 1_000_000_000.0)
    }

    private static func simulatorLastUsedAt(deviceDirectory: URL, fallbackMtime: timespec) -> Date? {
        let plistURL = deviceDirectory.appendingPathComponent("device.plist")
        if let device = DeviceStore.parseDevicePlist(at: plistURL, deviceDirectory: deviceDirectory),
           let lastUsedAt = device.lastUsedAt {
            return lastUsedAt
        }
        return date(from: fallbackMtime)
    }

    public static func readArchiveCreationDate(at archiveURL: URL) -> StalenessInfo {
        let infoPlistURL = archiveURL.appendingPathComponent("Info.plist")
        if let data = try? Data(contentsOf: infoPlistURL),
           let plist = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any],
           let creationDate = plist["CreationDate"] as? Date {
            return StalenessInfo(lastUsedDate: creationDate)
        }

        var statBuf = stat()
        if lstat(archiveURL.path(percentEncoded: false), &statBuf) == 0 {
            return StalenessInfo(lastUsedDate: date(from: statBuf.st_mtimespec))
        }

        return StalenessInfo(lastUsedDate: nil)
    }

    private static func newestChildMtime(at url: URL) -> Date? {
        let path = url.standardizedFileURL.resolvingSymlinksInPath().path(percentEncoded: false)
        guard let dir = opendir(path) else { return nil }
        defer { closedir(dir) }

        var maxMtime: Date?
        while let entry = readdir(dir) {
            guard let name = Dirent.name(of: entry) else { continue }
            if name == "." || name == ".." { continue }

            let childPath = (path as NSString).appendingPathComponent(name)
            var statBuf = stat()
            if lstat(childPath, &statBuf) == 0 {
                let mtime = date(from: statBuf.st_mtimespec)
                if let current = maxMtime {
                    if mtime > current { maxMtime = mtime }
                } else {
                    maxMtime = mtime
                }
            }
        }
        return maxMtime
    }

    private static func defaultConsequence(tier: Tier, name _: String) -> String {
        switch tier {
        case .regen:
            "Xcode recreates this on the next build."
        case .judgment:
            "Deleting this requires re-downloading or reinstalling if needed again."
        case .irreversible:
            "Deletes the dSYMs for this build. Crash reports from it can never be symbolicated again."
        case .reveal:
            "Reveal in Finder."
        case .info:
            "Root-owned. Run sudo command in Terminal to delete."
        }
    }
}
