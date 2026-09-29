import Foundation

public extension DeletionPlanner {
    /// Plans a clear of the known-bloat sub-paths inside a shut-down simulator.
    static func simulatorBloat(
        for device: SimDevice,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try KnownBloat.createBloatDeletionPlan(
            for: device,
            protectedPaths: context.protectedPaths,
            policyGeneration: context.policyGeneration
        )
    }

    /// Plans an erase of a simulator's installed apps and data.
    static func simulatorErase(
        for device: SimDevice,
        size: Int64 = 0,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try rejectProtectedDescendants(of: device, protectedPaths: context.protectedPaths)
        let udid = try SimctlIdentifier.validatedUDID(device.udid)
        let label = device.state.isBooted ? "Shut Down and Erase" : "Delete Permanently"
        let target = DeletionTarget.simulatorErase(
            udid: udid,
            name: device.name,
            isBooted: device.state.isBooted,
            consequence: device.state.isBooted
                ? "Shuts this simulator down, then removes all installed apps and their data."
                : "Removes all installed apps and their data from this simulator.",
            reclaimableBytes: size
        )
        return DeletionPlan.plannedSingle(
            target,
            confirmLabel: label,
            affectedLocationIds: [LocationCatalog.simulatorDevices.id],
            policyGeneration: context.policyGeneration
        )
    }

    /// Plans a complete deletion of a simulator device.
    static func simulatorDelete(
        for device: SimDevice,
        size: Int64 = 0,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try rejectProtectedDescendants(of: device, protectedPaths: context.protectedPaths)
        let udid = try SimctlIdentifier.validatedUDID(device.udid)
        let target = DeletionTarget.simulatorDelete(
            udid: udid,
            name: device.name,
            isBooted: device.state.isBooted,
            consequence: "Deletes this simulator completely. Installed apps and configuration will be permanently lost.",
            reclaimableBytes: size
        )
        return DeletionPlan.plannedSingle(
            target,
            confirmLabel: "Delete Permanently",
            affectedLocationIds: [LocationCatalog.simulatorDevices.id],
            policyGeneration: context.policyGeneration
        )
    }

    /// Plans the deletion of an installed runtime.
    static func runtimeDelete(
        _ runtime: SimRuntime,
        context: PlanningContext
    ) throws -> DeletionPlan {
        guard runtime.isDeletable else {
            throw DeletionPlanningError.runtimeNotDeletable(name: runtime.name)
        }
        guard !runtime.state.isBeingDeleted else {
            throw DeletionPlanningError.runtimeBeingDeleted(name: runtime.name)
        }
        guard !context.protectedPaths.containsCustomProtectedPath(in: systemRuntimeStore) else {
            throw DeletionPlanningError.protectedDescendantInSimulator(
                name: runtime.name,
                path: systemRuntimeStore.path
            )
        }
        let identifier = try SimctlIdentifier.validatedRuntime(runtime.identifier)
        let target = DeletionTarget.runtimeDelete(
            identifier: identifier,
            name: runtime.name,
            consequence: "Deletes the \(runtime.name) simulator runtime (\(ByteFormatter.format(runtime.sizeBytes))). " +
                "It must be re-downloaded to run simulators on this OS version. " +
                "Simulators that use it stop working until it is installed again.",
            reclaimableBytes: runtime.sizeBytes
        )
        // Runtime deletion also invalidates device availability.
        return DeletionPlan.plannedSingle(
            target,
            confirmLabel: "Delete Permanently",
            affectedLocationIds: [LocationCatalog.simulatorRuntimes.id, LocationCatalog.simulatorDevices.id],
            policyGeneration: context.policyGeneration
        )
    }

    /// Everything `simctl runtime delete` can touch lives under here.
    internal static let systemRuntimeStore = URL(
        fileURLWithPath: "/Library/Developer/CoreSimulator",
        isDirectory: true
    )

    private static func rejectProtectedDescendants(
        of device: SimDevice,
        protectedPaths: ProtectedPaths
    ) throws {
        guard !protectedPaths.containsCustomProtectedPath(in: device.deviceDirectory) else {
            throw DeletionPlanningError.protectedDescendantInSimulator(
                name: device.name,
                path: device.deviceDirectory.path
            )
        }
    }
}
