import Foundation

extension DeletionPlanner {
    /// Plans one Gradle cache entry after the user has acknowledged the direct-deletion risk.
    public static func gradleCacheChildAfterRiskAcknowledgement(
        _ child: ChildEntry,
        in location: TrackedLocation,
        context: PlanningContext
    ) throws -> DeletionPlan {
        guard location.id == LocationCatalog.gradleCaches.id,
              location.platform == .android,
              location.mutationPolicy == .readOnly
        else {
            throw DeletionPlanningError.readOnlyLocation(title: location.title)
        }

        let roots = location.resolveRoots()
        guard GradleCacheEntryPolicy.isEligible(child, cacheRoots: roots),
              let cacheRoot = roots.first(where: {
                  ProtectedPaths.normalize(child.url.deletingLastPathComponent())
                      == ProtectedPaths.normalize($0)
              })
        else {
            throw DeletionPlanningError.unrecognizedGradleCacheEntry(name: child.name)
        }

        let pathGuard = PathGuard(roots: [], protectedPaths: context.protectedPaths)
        let validated: ValidatedPath
        do {
            validated = try pathGuard.validateGradleCacheEntry(child.url)
        } catch let error as PathGuardError {
            throw DeletionPlanningError.refused(name: child.name, error: error)
        }
        guard let fingerprint = Fingerprint.capture(at: child.url) else {
            throw DeletionPlanningError.missingOnDisk(name: child.name)
        }

        let consequence = "Gradle may be using this cache now. Clearing it can interrupt builds, "
            + "force rebuilds or downloads, and make offline builds fail. "
            + "Cruftless cannot guarantee project integrity. Approved for this attempt only."
        let target = DeletionTarget.path(
            id: child.id,
            name: child.name,
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: .judgment,
            consequence: consequence,
            reclaimableBytes: child.reclaimableBytes
        )
        let acknowledgement = GradleCacheRiskAcknowledgement(
            child: child,
            cacheRoot: cacheRoot,
            policyGeneration: context.policyGeneration
        )
        return DeletionPlan.plannedSingle(
            target,
            confirmLabel: "Delete Permanently",
            affectedLocationIds: [location.id],
            policyGeneration: context.policyGeneration,
            gradleCacheRiskAcknowledgement: acknowledgement
        )
    }
}
