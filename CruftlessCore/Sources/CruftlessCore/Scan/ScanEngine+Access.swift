import Foundation

/// How a scan reports the roots the access gate kept it from opening, or that macOS refused.
extension ScanEngine {
    /// Passes `roots` through the gate, then scans what it cleared.
    nonisolated static func scanFilesystemLocation(
        _ location: TrackedLocation,
        roots: [URL],
        inodeSet: InodeSet,
        simulatorContext: SimulatorScanContext = SimulatorScanContext(),
        accessGate: AccessGate = .shared
    ) -> LocationOutcome {
        scanFilesystemLocation(
            location,
            gated: accessGate.partition(roots, for: location),
            inodeSet: inodeSet,
            simulatorContext: simulatorContext,
            accessGate: accessGate
        )
    }

    /// Cleared roots in an asked area that exist but report unreadable before any walk.
    nonisolated static func refusedRoots(_ gated: GatedRoots, readable: [URL], location: TrackedLocation) -> [BlockedAccess] {
        let readablePaths = Set(readable.map(ProtectedPaths.normalize))
        return gated.clear.compactMap { root in
            guard let area = gated.askedArea(of: root),
                  !readablePaths.contains(ProtectedPaths.normalize(root)),
                  FileManager.default.fileExists(atPath: root.path(percentEncoded: false))
            else { return nil }
            return notAllowed(root, area: area, location: location)
        }
    }

    /// Walked roots in an asked area that could not be opened at all, removed from the walk's rows and incomplete notice.
    nonisolated static func deniedRoots(_ gated: GatedRoots, walk: inout RootsWalk, location: TrackedLocation) -> [BlockedAccess] {
        let denied = walk.unopenedRoots.compactMap { root in
            gated.askedArea(of: root).map { notAllowed(root, area: $0, location: location) }
        }
        let deniedPaths = Set(denied.map { ProtectedPaths.normalize(URL(fileURLWithPath: $0.path)) })
        if let incomplete = walk.incomplete, deniedPaths.contains(ProtectedPaths.normalize(incomplete.root)) {
            walk.incomplete = nil
        }
        walk.rootSizes.removeAll { deniedPaths.contains(ProtectedPaths.normalize($0.url)) }
        for path in deniedPaths {
            walk.breakdowns[path] = nil
        }
        return denied
    }

    nonisolated static func accessNeed(_ blocked: [BlockedAccess], measuredRootCount: Int) -> LocationAccessNeed? {
        blocked.isEmpty ? nil : LocationAccessNeed(blocked: blocked, measuredRootCount: measuredRootCount)
    }

    nonisolated static func needsAccessOutcome(_ location: TrackedLocation, need: LocationAccessNeed) -> LocationOutcome {
        LocationOutcome(locationId: location.id, entry: .needsAccess(location: location, need: need), failure: nil)
    }

    nonisolated private static func notAllowed(_ root: URL, area: ProtectedArea, location: TrackedLocation) -> BlockedAccess {
        BlockedAccess(
            path: root.path(percentEncoded: false),
            area: area,
            state: .notAllowed,
            reason: AccessReason.title(for: location, root: root)
        )
    }
}
