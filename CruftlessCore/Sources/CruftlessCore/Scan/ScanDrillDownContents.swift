import Foundation

typealias RuntimeCatalogDeviceLister = @Sendable (SimulatorRuntimeListing, SimulatorDeviceSet) -> [SimDevice]

struct SimulatorScanContext: Sendable {
    var listing: SimulatorRuntimeListing?
    var failure: String?
    var deviceLister: RuntimeCatalogDeviceLister?
    var protectedPaths: ProtectedPaths = ProtectedPathsStore.shared.protectedPaths()
}

struct DrillDownScanContext: Sendable {
    let knownSizes: [String: [String: SizeResult]]
    let roots: [RootSize]
    let runtimeListing: SimulatorRuntimeListing?
    let runtimesFailure: String?
    let deviceLister: RuntimeCatalogDeviceLister?
    var accessGate: AccessGate = .shared
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
        location.sizeSource == .simulatorRuntimes || location.id == LocationCatalog.simulatorDevices.id || location.id == LocationCatalog
            .xctestDevices.id
    }

    /// The shared lookup's outcome, as two `Sendable` halves.
    static func resolveRuntimes(
        _ task: Task<SimulatorRuntimeListing, any Error>?
    ) async -> (list: SimulatorRuntimeListing?, failure: String?) {
        guard let task else { return (nil, nil) }
        do {
            return try await (task.value, nil)
        } catch {
            return (nil, error.localizedDescription)
        }
    }

    /// Walks only the roots the access gate cleared; a blocked root is reported, never opened.
    nonisolated static func scanFilesystemLocation(
        _ location: TrackedLocation,
        gated: GatedRoots,
        inodeSet: InodeSet,
        simulatorContext: SimulatorScanContext = SimulatorScanContext(),
        accessGate: AccessGate = .shared
    ) -> LocationOutcome {
        ScanSignposts.shared.measure("ScanLocation") {
            let readable = readableRoots(among: gated.clear)
            let refused = refusedRoots(gated, readable: readable.roots, location: location)

            if readable.roots.isEmpty {
                if let need = accessNeed(gated.blocked + refused, measuredRootCount: 0) {
                    return needsAccessOutcome(location, need: need)
                }
                return emptyFilesystemOutcome(location, unreadableReason: readable.unreadableReason)
            }

            var walked = walkRoots(
                location,
                readable.roots,
                inodeSet: inodeSet,
                recordingDepth: DrillDownProvider.sizeRecordingDepth(for: location)
            )
            let denied = deniedRoots(gated, walk: &walked, location: location)
            let measuredCount = readable.roots.count - denied.count
            let need = accessNeed(gated.blocked + refused + denied, measuredRootCount: measuredCount)
            if measuredCount == 0, let need {
                return needsAccessOutcome(location, need: need)
            }
            let contents = drillDownContents(for: location, walked: walked, simulatorContext: simulatorContext, accessGate: accessGate)
            let issues = [incompleteReason(for: location, walk: walked), contents?.inventoryIssue, need?.message]
                .compactMap(\.self)
            return LocationOutcome(
                locationId: location.id,
                entry: .sized(
                    location: location,
                    reclaimableBytes: walked.totalAllocated,
                    staleness: staleness(for: location, roots: walked.rootSizes.map(\.url), newestMtime: walked.newestMtime),
                    roots: walked.rootSizes,
                    eligibleCleanupBytes: location.id == LocationCatalog.xctestDevices.id
                        ? eligibleTestDeviceBytes(contents, protectedPaths: simulatorContext.protectedPaths)
                        : nil,
                    accessNeed: need
                ),
                failure: issues.isEmpty ? nil : issues.joined(separator: " "),
                childBreakdowns: walked.breakdowns,
                contents: contents
            )
        }
    }

    nonisolated private static func drillDownContents(
        for location: TrackedLocation,
        walked: RootsWalk,
        simulatorContext: SimulatorScanContext,
        accessGate: AccessGate
    ) -> DrillDownContent? {
        drillDownContents(
            for: location,
            context: DrillDownScanContext(
                knownSizes: walked.breakdowns,
                roots: walked.rootSizes,
                runtimeListing: simulatorContext.listing,
                runtimesFailure: simulatorContext.failure,
                deviceLister: simulatorContext.deviceLister,
                accessGate: accessGate
            )
        )
    }

    nonisolated static func eligibleTestDeviceBytes(_ contents: DrillDownContent?, protectedPaths: ProtectedPaths) -> Int64 {
        guard case let .devices(devices, sizes) = contents else { return 0 }
        let context = PlanningContext(protectedPaths: protectedPaths)
        return devices.reduce(0) { total, device in
            guard let size = sizes[device.udid], size > 0 else { return total }
            do {
                _ = try DeletionPlanner.xctestSimulatorDelete(for: device, size: size, context: context)
                return total + size
            } catch { return total }
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
                in: context.accessGate.clearRoots(context.roots.map(\.url)),
                rootSizes: context.roots,
                knownSizes: context.knownSizes
            )
            if !scan.diagnostics.isEmpty {
                let issue = scan.issue ?? "Some SDK contents could not be classified."
                return .childrenWithDiagnostics(
                    scan.children,
                    summary: issue,
                    scan.diagnostics,
                    totalCount: scan.diagnosticCount,
                    truncated: scan.diagnosticsTruncated
                )
            }
            if let issue = scan.issue { return .childrenWithIssue(scan.children, issue) }
            return .children(scan.children)
        }

        if location.id == "androidAVDs" {
            let children = DrillDownProvider.androidAVDs(
                in: context.accessGate.clearRoots(context.roots.map(\.url)),
                rootSizes: context.roots,
                knownSizes: context.knownSizes,
                accessGate: context.accessGate
            )
            if let issue = location.discoveryIssue() { return .childrenWithIssue(children, issue) }
            return .children(children)
        }

        guard location.id == LocationCatalog.simulatorDevices.id || location.id == LocationCatalog.xctestDevices.id else {
            return .children(DrillDownProvider.loadChildren(
                for: location,
                roots: context.roots.map(\.url),
                knownSizes: context.knownSizes,
                accessGate: context.accessGate
            ))
        }

        guard let runtimeListing = context.runtimeListing, let deviceLister = context.deviceLister else {
            return .unavailable(context.runtimesFailure ?? "Could not read the installed simulator runtimes.")
        }

        return .devices(
            deviceLister(runtimeListing, location.id == LocationCatalog.xctestDevices.id ? .xctest() : .ordinary()),
            sizes: immediateChildSizes(in: context.knownSizes)
        )
    }
}
