import Foundation

extension DeletionPlanner {
    /// Plans a clear of the known-bloat sub-paths inside a shut-down simulator.
    public static func simulatorBloat(
        for device: SimDevice,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try KnownBloat.createBloatDeletionPlan(for: device, protectedPaths: context.protectedPaths)
    }

    /// Plans an erase of a simulator's installed apps and data.
    public static func simulatorErase(
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
        return DeletionPlan.single(target, confirmLabel: label)
    }

    /// Plans a complete deletion of a simulator device.
    public static func simulatorDelete(
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
        return DeletionPlan.single(target, confirmLabel: "Delete Permanently")
    }

    /// Plans the deletion of an installed runtime.
    public static func runtimeDelete(
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
        return DeletionPlan.single(target, confirmLabel: "Delete Permanently")
    }

    /// Everything `simctl runtime delete` can touch lives under here.
    static let systemRuntimeStore = URL(
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
