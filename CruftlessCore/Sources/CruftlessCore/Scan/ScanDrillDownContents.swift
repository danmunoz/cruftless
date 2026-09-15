import Foundation

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
                if let reason = readable.unreadableReason {
                    return LocationOutcome(
                        locationId: location.id,
                        entry: .unavailable(location: location, reason: reason),
                        failure: nil
                    )
                }
                return LocationOutcome(locationId: location.id, entry: nil, failure: nil)
            }

            let walked = walkRoots(
                readable.roots,
                inodeSet: inodeSet,
                recordingDepth: DrillDownProvider.sizeRecordingDepth(for: location)
            )

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
                failure: walked.incomplete.map {
                    incompleteScanReason(root: $0.root, result: $0.result)
                },
                childBreakdowns: walked.breakdowns,
                contents: drillDownContents(
                    for: location,
                    knownSizes: walked.breakdowns,
                    runtimes: runtimes,
                    runtimesFailure: runtimesFailure,
                    deviceLister: deviceLister
                )
            )
        }
    }

    nonisolated static func drillDownContents(
        for location: TrackedLocation,
        knownSizes: [String: [String: SizeResult]],
        runtimes: [SimRuntime]?,
        runtimesFailure: String?,
        deviceLister: DeviceLister?
    ) -> DrillDownContent? {
        guard location.hasDrillDown else { return nil }

        guard location.id == LocationCatalog.simulatorDevices.id else {
            return .children(DrillDownProvider.loadChildren(for: location, knownSizes: knownSizes))
        }

        guard let runtimes, let deviceLister else {
            return .unavailable(runtimesFailure ?? "Could not read the installed simulator runtimes.")
        }

        return .devices(
            deviceLister(runtimes),
            sizes: immediateChildSizes(in: knownSizes)
        )
    }
}
