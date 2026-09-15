import Foundation

/// Builds review-ready `DeletionPlan`s from what a screen has on hand.
public enum DeletionPlanner {
    /// Plans a clear of every root belonging to one tracked location.
    public static func wholeLocation(
        _ entry: InventoryEntry,
        context: PlanningContext
    ) throws -> DeletionPlan {
        let location = entry.location
        guard location.tier.isDeletable else {
            throw DeletionPlanningError.notDeletable(title: location.title)
        }
        if let reason = entry.unavailableReason {
            throw DeletionPlanningError.unavailable(title: location.title, reason: reason)
        }

        guard !location.tier.isFlagged else {
            throw DeletionPlanningError.flaggedLocation(title: location.title)
        }

        try requirePathDeletion(location)

        let pathGuard = PathGuard(roots: location.resolveRoots(), protectedPaths: context.protectedPaths)
        var targets: [DeletionTarget] = []
        for root in entry.roots {
            if location.isCustomRoot(root.url) {
                try targets.append(contentsOf: customRootTargets(
                    under: root.url,
                    location: location,
                    children: context.childrenProvider(location),
                    pathGuard: pathGuard,
                    context: context
                ))
                continue
            }
            try targets.append(defaultRootTarget(
                root,
                entry: entry,
                pathGuard: pathGuard,
                context: context
            ))
        }

        try rejectOverlaps(among: targets)
        let plan = DeletionPlan.batch(targets)
        guard !plan.isEmpty else {
            throw DeletionPlanningError.nothingToPlan(title: location.title)
        }
        return plan
    }

    /// The single target for one of the location's own roots: the folder itself, through `validateRoot`.
    private static func defaultRootTarget(
        _ root: RootSize,
        entry: InventoryEntry,
        pathGuard: PathGuard,
        context: PlanningContext
    ) throws -> DeletionTarget {
        let location = entry.location
        let name = entry.roots.count > 1
            ? "\(location.title) · \(root.url.lastPathComponent)"
            : location.title
        let validated: ValidatedPath
        do {
            validated = try pathGuard.validateRoot(root.url)
        } catch let error as PathGuardError {
            throw DeletionPlanningError.refused(name: name, error: error)
        }
        guard let fingerprint = Fingerprint.capture(at: root.url) else {
            throw DeletionPlanningError.missingOnDisk(name: name)
        }
        return .path(
            id: "\(entry.id)-\(root.url.lastPathComponent)",
            name: name,
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: location.tier,
            // The copy is the location's own (`LocationCatalog`); the planner only prepends the active-toolchain warning to it.
            consequence: toolchainAwareConsequence(
                base: location.consequence,
                location: location,
                targetURL: root.url,
                activeToolchainOverrideIdentifier: context.activeToolchainOverrideIdentifier
            ),
            reclaimableBytes: root.allocatedBytes
        )
    }

    /// The per-child targets for a redirected root.
    private static func customRootTargets(
        under root: URL,
        location: TrackedLocation,
        children: [ChildEntry],
        pathGuard: PathGuard,
        context: PlanningContext
    ) throws -> [DeletionTarget] {
        let rootPrefix = ProtectedPaths.normalize(root) + "/"
        let inside = children.filter { ProtectedPaths.normalize($0.url).hasPrefix(rootPrefix) }
        return try inside.map { child in
            try target(
                for: child,
                in: location,
                pathGuard: pathGuard,
                context: context,
                displayName: "\(location.title) · \(child.name)"
            )
        }
    }

    /// Plans a clear of a single drill-down child.
    public static func child(
        _ child: ChildEntry,
        in location: TrackedLocation,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try requireDeletableLocation(location)
        try requirePathDeletion(location)
        let pathGuard = PathGuard(roots: location.resolveRoots(), protectedPaths: context.protectedPaths)
        return try DeletionPlan.single(target(
            for: child,
            in: location,
            pathGuard: pathGuard,
            context: context
        ))
    }

    /// Plans a clear of several drill-down children at once.
    public static func children(
        _ children: [ChildEntry],
        in location: TrackedLocation,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try requireDeletableLocation(location)
        try requirePathDeletion(location)
        let pathGuard = PathGuard(roots: location.resolveRoots(), protectedPaths: context.protectedPaths)
        let targets = try children.map {
            try target(
                for: $0,
                in: location,
                pathGuard: pathGuard,
                context: context
            )
        }
        try rejectOverlaps(among: targets)

        let plan = DeletionPlan.batch(targets)
        guard !plan.isEmpty else {
            throw DeletionPlanningError.nothingToPlan(title: location.title)
        }
        return plan
    }

    /// Refuses a batch whose targets are not disjoint.
    private static func rejectOverlaps(among targets: [DeletionTarget]) throws {
        var seen: [String: String] = [:]
        for target in targets {
            guard let path = target.validatedPath?.path else { continue }
            if seen[path] != nil {
                throw DeletionPlanningError.duplicateTarget(name: target.name)
            }
            seen[path] = target.name
        }

        for (path, name) in seen {
            for (otherPath, otherName) in seen where path.hasPrefix(otherPath + "/") {
                throw DeletionPlanningError.nestedTargets(outer: otherName, inner: name)
            }
        }
    }

    private static func requireDeletableLocation(_ location: TrackedLocation) throws {
        guard location.tier.isDeletable else {
            throw DeletionPlanningError.notDeletable(title: location.title)
        }
    }

    private static func requirePathDeletion(_ location: TrackedLocation) throws {
        guard location.mutationPolicy == .pathDeletion else {
            throw DeletionPlanningError.simulatorLocation(title: location.title)
        }
    }

    private static func target(
        for child: ChildEntry,
        in location: TrackedLocation,
        pathGuard: PathGuard,
        context: PlanningContext,
        displayName: String? = nil
    ) throws -> DeletionTarget {
        guard child.tier.isDeletable else {
            throw DeletionPlanningError.notDeletable(title: child.name)
        }

        let validated: ValidatedPath
        do {
            validated = try pathGuard.validate(child.url)
        } catch let error as PathGuardError {
            throw DeletionPlanningError.refused(name: child.name, error: error)
        }
        guard let fingerprint = Fingerprint.capture(at: child.url) else {
            throw DeletionPlanningError.missingOnDisk(name: child.name)
        }
        return .path(
            id: child.id,
            name: displayName ?? child.name,
            validatedPath: validated,
            fingerprint: fingerprint,
            tier: child.tier,
            consequence: toolchainAwareConsequence(
                base: child.consequence,
                location: location,
                targetURL: child.url,
                activeToolchainOverrideIdentifier: context.activeToolchainOverrideIdentifier
            ),
            reclaimableBytes: child.reclaimableBytes
        )
    }
}
