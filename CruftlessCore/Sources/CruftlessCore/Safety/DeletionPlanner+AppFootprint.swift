import Foundation

public extension DeletionPlanner {
    /// Plans the removal of every footprint folder that exists, each as a root of its own.
    ///
    /// An absent folder is skipped. Any folder the guard refuses refuses the whole plan.
    static func appFootprint(
        _ footprint: AppFootprint,
        context: PlanningContext,
        exists: (URL) -> Bool = AppFootprintPlanning.existsWithoutFollowingLinks,
        size: (URL) -> Int64 = AppFootprintPlanning.allocatedSize
    ) throws -> DeletionPlan {
        let present = footprint.folders.filter { exists($0.url) }
        let pathGuard = PathGuard(roots: present.map(\.url), protectedPaths: context.protectedPaths)
        let targets: [DeletionTarget] = try present.map { folder in
            let validated: ValidatedPath
            do {
                validated = try pathGuard.validateRoot(folder.url)
            } catch let error as PathGuardError {
                throw DeletionPlanningError.refused(name: folder.title, error: error)
            }
            guard let fingerprint = Fingerprint.capture(at: folder.url) else {
                throw DeletionPlanningError.missingOnDisk(name: folder.title)
            }
            return .path(
                id: "app-footprint-\(folder.id)",
                name: folder.title,
                validatedPath: validated,
                fingerprint: fingerprint,
                tier: .regen,
                consequence: folder.consequence,
                reclaimableBytes: size(folder.url)
            )
        }
        try rejectOverlaps(among: targets)
        return DeletionPlan.plannedBatch(
            targets,
            confirmLabel: "Remove Cruftless Data",
            policyGeneration: context.policyGeneration
        )
    }
}

/// Filesystem reads for planning a footprint removal.
public enum AppFootprintPlanning {
    /// `lstat` only, so a symlinked folder still reaches the guard and is refused there.
    public static func existsWithoutFollowingLinks(_ url: URL) -> Bool {
        var info = stat()
        return lstat(url.path(percentEncoded: false), &info) == 0
    }

    public static func allocatedSize(_ url: URL) -> Int64 {
        DirectoryWalker.walk(url: url, inodeSet: InodeSet()).allocatedBytes
    }
}
