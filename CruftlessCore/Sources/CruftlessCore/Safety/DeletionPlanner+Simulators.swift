import Foundation

public extension DeletionPlanner {
    /// Plans an explicitly selected set of simulator devices in one authorized batch.
    static func simulatorDevices(
        _ devices: [(device: SimDevice, size: Int64)],
        context: PlanningContext
    ) throws -> DeletionPlan {
        guard !devices.isEmpty else {
            throw DeletionPlanningError.nothingToPlan(title: LocationCatalog.simulatorDevices.title)
        }

        let identifiers = try devices.map { try SimctlIdentifier.validatedUDID($0.device.udid) }
        guard Set(identifiers).count == identifiers.count else {
            throw DeletionPlanningError.duplicateTarget(name: LocationCatalog.simulatorDevices.title)
        }

        var plans: [DeletionPlan] = []
        for (device, size) in devices {
            plans.append(try device.isUnavailable
                ? simulatorDelete(for: device, size: size, context: context)
                : simulatorErase(for: device, size: size, context: context))
        }

        let generations = Set(plans.compactMap(\.simulatorToolchainGeneration))
        guard generations.count <= 1,
              plans.allSatisfy({ $0.simulatorToolchainGeneration != nil })
        else {
            throw DeletionPlanningError.simulatorToolchainMismatch
        }

        let hasDelete = devices.contains { $0.device.isUnavailable }
        let hasErase = devices.contains { !$0.device.isUnavailable }
        let hasBooted = devices.contains { $0.device.state.isBooted }
        let label: String
        switch (hasDelete, hasErase) {
        case (true, true): label = hasBooted ? "Shut Down, Delete and Erase" : "Delete and Erase"
        case (true, false): label = "Delete Permanently"
        case (false, true) where devices.contains(where: { $0.device.state.isBooted }):
            label = "Shut Down and Erase"
        case (false, true): label = "Erase Permanently"
        case (false, false):
            throw DeletionPlanningError.nothingToPlan(title: LocationCatalog.simulatorDevices.title)
        }

        return .plannedBatch(
            plans.flatMap(\.items),
            confirmLabel: label,
            affectedLocationIds: [LocationCatalog.simulatorDevices.id],
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: generations.first
        )
    }

    /// Plans an explicitly selected set of installed runtimes in one authorized batch.
    static func simulatorRuntimes(_ runtimes: [SimRuntime], context: PlanningContext) throws -> DeletionPlan {
        guard !runtimes.isEmpty else {
            throw DeletionPlanningError.nothingToPlan(title: LocationCatalog.simulatorRuntimes.title)
        }
        let identifiers = try runtimes.map { try SimctlIdentifier.validatedRuntime($0.identifier) }
        guard Set(identifiers).count == identifiers.count else {
            throw DeletionPlanningError.duplicateTarget(name: LocationCatalog.simulatorRuntimes.title)
        }

        let plans = try runtimes.map { try runtimeDelete($0, context: context) }
        let generations = Set(plans.compactMap(\.simulatorToolchainGeneration))
        guard generations.count <= 1,
              plans.allSatisfy({ $0.simulatorToolchainGeneration != nil })
        else {
            throw DeletionPlanningError.simulatorToolchainMismatch
        }

        return .plannedBatch(
            plans.flatMap(\.items),
            confirmLabel: "Delete Permanently",
            affectedLocationIds: [LocationCatalog.simulatorRuntimes.id, LocationCatalog.simulatorDevices.id],
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: generations.first
        )
    }

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
        try rejectToolchainIssue(of: device)
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
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: device.toolchainGeneration
        )
    }

    /// Plans a complete deletion of a simulator device.
    static func simulatorDelete(
        for device: SimDevice,
        size: Int64 = 0,
        context: PlanningContext
    ) throws -> DeletionPlan {
        try rejectToolchainIssue(of: device)
        try rejectProtectedDescendants(of: device, protectedPaths: context.protectedPaths)
        let udid = try SimctlIdentifier.validatedUDID(device.udid)
        let target = DeletionTarget.simulatorDelete(
            udid: udid,
            name: device.name,
            isBooted: device.state.isBooted,
            consequence: device.state.isBooted
                ? "Shuts this simulator down, then deletes it completely. Installed apps and configuration will be permanently lost."
                : "Deletes this simulator completely. Installed apps and configuration will be permanently lost.",
            reclaimableBytes: size
        )
        return DeletionPlan.plannedSingle(
            target,
            confirmLabel: "Delete Permanently",
            affectedLocationIds: [LocationCatalog.simulatorDevices.id],
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: device.toolchainGeneration
        )
    }

    /// Plans the deletion of an installed runtime.
    static func runtimeDelete(
        _ runtime: SimRuntime,
        context: PlanningContext
    ) throws -> DeletionPlan {
        if case let .unavailable(reason) = runtime.mutationCapability {
            throw DeletionPlanningError.runtimeToolingUnavailable(name: runtime.name, reason: reason)
        }
        guard runtime.isDeletable else {
            throw DeletionPlanningError.runtimeNotDeletable(name: runtime.name)
        }
        guard !runtime.state.isBeingDeleted else {
            throw DeletionPlanningError.runtimeBeingDeleted(name: runtime.name)
        }
        guard !context.protectedPaths.intersectsCustomProtection(systemRuntimeStore),
              !context.protectedPaths.containsCustomProtectedPath(in: systemRuntimeStore)
        else {
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
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: runtime.toolchainGeneration
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
        guard !protectedPaths.intersectsCustomProtection(device.deviceDirectory),
              !protectedPaths.containsCustomProtectedPath(in: device.deviceDirectory)
        else {
            throw DeletionPlanningError.protectedDescendantInSimulator(
                name: device.name,
                path: device.deviceDirectory.path
            )
        }
    }

    private static func rejectToolchainIssue(of device: SimDevice) throws {
        if let reason = device.mutationIssue {
            throw DeletionPlanningError.runtimeToolingUnavailable(name: device.name, reason: reason)
        }
    }
}
