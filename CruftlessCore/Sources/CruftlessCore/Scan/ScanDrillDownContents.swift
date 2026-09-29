import Foundation

struct DrillDownScanContext: Sendable {
    let knownSizes: [String: [String: SizeResult]]
    let roots: [RootSize]
    let runtimes: [SimRuntime]?
    let runtimesFailure: String?
    let deviceLister: ScanEngine.DeviceLister?
}

/// The half of a scan that produces what a drill-down will render, and the per-location walk that feeds it.
extension ScanEngine {
    /// `nonisolated`, so the scan can build the same table off the actor while it still has the breakdowns in hand.
    nonisolated static func immediateChildSizes(
        in byRoot: [String: [String: SizeResult]]
    ) -> [String: Int64] {
        var flattened: [String: Int64] = [:]
        for (rootPath, measured) in byRoot {
            for (measuredPath, size) in measured {
                guard (measuredPath as NSString).deletingLastPathComponent == rootPath else { continue }
                flattened[(measuredPath as NSString).lastPathComponent, default: 0] += size.allocatedBytes
            }
        }
        return flattened
    }

    /// Whether this location's scan depends on the shared runtime lookup.
    nonisolated static func needsRuntimes(_ location: TrackedLocation) -> Bool {
        location.sizeSource == .simulatorRuntimes || location.id == LocationCatalog.simulatorDevices.id
    }

    /// The shared lookup's outcome, as two `Sendable` halves.
    static func resolveRuntimes(
        _ task: Task<[SimRuntime], any Error>?
    ) async -> (list: [SimRuntime]?, failure: String?) {
        guard let task else { return (nil, nil) }
        do {
            return (try await task.value, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    nonisolated static func scanFilesystemLocation(
        _ location: TrackedLocation,
        roots: [URL],
        inodeSet: InodeSet,
        runtimes: [SimRuntime]? = nil,
        runtimesFailure: String? = nil,
        deviceLister: DeviceLister? = nil
    ) -> LocationOutcome {
        ScanSignposts.shared.measure("ScanLocation") {
            let readable = readableRoots(among: roots)

            if readable.roots.isEmpty {
                return emptyFilesystemOutcome(location, unreadableReason: readable.unreadableReason)
            }

            let walked = walkRoots(
                location,
                readable.roots,
                inodeSet: inodeSet,
                recordingDepth: DrillDownProvider.sizeRecordingDepth(for: location)
            )
            let contents = drillDownContents(
                for: location,
                context: DrillDownScanContext(
                    knownSizes: walked.breakdowns,
                    roots: walked.rootSizes,
                    runtimes: runtimes,
                    runtimesFailure: runtimesFailure,
                    deviceLister: deviceLister
                )
            )
            let issues = [incompleteReason(for: location, walk: walked), contents?.inventoryIssue]
                .compactMap { $0 }
            return LocationOutcome(
                locationId: location.id,
                entry: .sized(
                    location: location,
                    reclaimableBytes: walked.totalAllocated,
                    staleness: staleness(
                        for: location,
                        roots: readable.roots,
                        newestMtime: walked.newestMtime
                    ),
                    roots: walked.rootSizes
                ),
                failure: issues.isEmpty ? nil : issues.joined(separator: " "),
                childBreakdowns: walked.breakdowns,
                contents: contents
            )
        }
    }

    nonisolated private static func emptyFilesystemOutcome(
        _ location: TrackedLocation,
        unreadableReason: String?
    ) -> LocationOutcome {
        if let issue = location.discoveryIssue() {
            return LocationOutcome(
                locationId: location.id,
                entry: .unavailable(location: location, reason: issue),
                failure: nil,
                contents: .unavailable(issue)
            )
        }
        if let unreadableReason {
            return LocationOutcome(
                locationId: location.id,
                entry: .unavailable(location: location, reason: unreadableReason),
                failure: nil
            )
        }
        return LocationOutcome(locationId: location.id, entry: nil, failure: nil)
    }

    nonisolated static func drillDownContents(
        for location: TrackedLocation,
        context: DrillDownScanContext
    ) -> DrillDownContent? {
        guard location.hasDrillDown else { return nil }

        if location.id == "androidSDK" {
            let scan = DrillDownProvider.androidSDKPackages(
                in: context.roots.map(\.url),
                rootSizes: context.roots,
                knownSizes: context.knownSizes
            )
            if let issue = scan.issue { return .childrenWithIssue(scan.children, issue) }
            return .children(scan.children)
        }

        if location.id == "androidAVDs" {
            let children = DrillDownProvider.androidAVDs(
                in: context.roots.map(\.url),
                rootSizes: context.roots,
                knownSizes: context.knownSizes
            )
            if let issue = location.discoveryIssue() { return .childrenWithIssue(children, issue) }
            return .children(children)
        }

        guard location.id == LocationCatalog.simulatorDevices.id else {
            return .children(DrillDownProvider.loadChildren(for: location, knownSizes: context.knownSizes))
        }

        guard let runtimes = context.runtimes, let deviceLister = context.deviceLister else {
            return .unavailable(context.runtimesFailure ?? "Could not read the installed simulator runtimes.")
        }

        return .devices(
            deviceLister(runtimes),
            sizes: immediateChildSizes(in: context.knownSizes)
        )
    }
}
