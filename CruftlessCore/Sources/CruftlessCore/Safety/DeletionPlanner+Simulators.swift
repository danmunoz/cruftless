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

        _ = try devices.map { try SimctlIdentifier.validatedUDID($0.device.udid) }
        let scopedIDs = devices.map { "\($0.device.deviceSet.id):\($0.device.udid)" }
        guard Set(scopedIDs).count == scopedIDs.count else {
            throw DeletionPlanningError.duplicateTarget(name: LocationCatalog.simulatorDevices.title)
        }

        var plans: [DeletionPlan] = []
        for (device, size) in devices {
            if case let .unknown(reason) = device.runtimeAvailability {
                throw DeletionPlanningError.runtimeToolingUnavailable(name: device.name, reason: reason)
            }
            if device.deviceSet.kind == .xctest {
                try plans.append(xctestSimulatorDelete(for: device, size: size, context: context))
            } else {
                try plans.append(device.runtimeAvailability.isConfirmedMissing
                    ? simulatorDelete(for: device, size: size, context: context)
                    : simulatorErase(for: device, size: size, context: context))
            }
        }

        let generations = Set(plans.compactMap(\.simulatorToolchainGeneration))
        guard generations.count <= 1,
              plans.allSatisfy({ $0.simulatorToolchainGeneration != nil })
        else {
            throw DeletionPlanningError.simulatorToolchainMismatch
        }

        let label = try simulatorDeviceBatchLabel(devices)

        return .plannedBatch(
            plans.flatMap(\.items),
            confirmLabel: label,
            affectedLocationIds: [devices[0].device.deviceSet.locationID],
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: generations.first
        )
    }

    private static func simulatorDeviceBatchLabel(_ devices: [(device: SimDevice, size: Int64)]) throws -> String {
        let hasTestDelete = devices.contains { $0.device.deviceSet.kind == .xctest }
        guard Set(devices.map(\.device.deviceSet.kind)).count == 1 else {
            throw DeletionPlanningError.duplicateTarget(name: "Simulator devices from different device sets")
        }
        let hasDelete = devices.contains { $0.device.runtimeAvailability.isConfirmedMissing }
        let hasErase = devices.contains { !$0.device.runtimeAvailability.isConfirmedMissing }
        let hasBooted = devices.contains { $0.device.state.isBooted }
        let label: String
        switch (hasTestDelete, hasDelete, hasErase) {
        case (true, _, _): label = "Delete Test Simulator"
        case (false, true, true): label = hasBooted ? "Shut Down, Delete and Erase" : "Delete and Erase"
        case (false, true, false): label = "Delete Permanently"
        case (false, false, true) where devices.contains(where: \.device.state.isBooted):
            label = "Shut Down and Erase"
        case (false, false, true): label = "Erase Permanently"
        case (false, false, false):
            throw DeletionPlanningError.nothingToPlan(title: LocationCatalog.simulatorDevices.title)
        }

        return label
    }

    static func xctestSimulatorDelete(for device: SimDevice, size: Int64, context: PlanningContext) throws -> DeletionPlan {
        guard device.deviceSet.kind == .xctest, device.deviceSet.isProductionRoot,
              device.state.isShutdown, device.toolchainGeneration != nil,
              let currentDevice = DeviceStore.parseDevicePlist(at: device.deviceDirectory.appendingPathComponent("device.plist"),
                                                               deviceDirectory: device.deviceDirectory, deviceSet: device.deviceSet),
              currentDevice.udid == device.udid, currentDevice.state.isShutdown else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: device.name,
                reason: "Test simulators must be shut down and identified in Xcode's XCTest device set before deletion."
            )
        }
        try rejectToolchainIssue(of: device)
        try requireRuntimeAvailabilityAuthority(for: device)
        try rejectProtectedDescendants(of: device, protectedPaths: context.protectedPaths)
        let udid = try SimctlIdentifier.validatedUDID(device.udid)
        guard let deviceFingerprint = Fingerprint.capture(at: device.deviceDirectory),
              let plistFingerprint = Fingerprint.capture(at: device.deviceDirectory.appendingPathComponent("device.plist")) else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: device.name,
                reason: "Test simulator identity could not be verified for review."
            )
        }
        return .plannedSingle(
            .xctestSimulatorDelete(deviceSet: device.deviceSet,
                                   udid: udid,
                                   deviceDirectory: device.deviceDirectory,
                                   deviceFingerprint: deviceFingerprint,
                                   plistFingerprint: plistFingerprint,
                                   name: device.name,
                                   consequence: "Permanently deletes this retained Xcode test simulator, " +
                                       "including its apps, data and snapshots.",
                                   reclaimableBytes: size),
            confirmLabel: "Delete Test Simulator",
            affectedLocationIds: [LocationCatalog.xctestDevices.id],
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: device.toolchainGeneration
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
            affectedLocationIds: [LocationCatalog.simulatorRuntimes.id, LocationCatalog.simulatorDevices.id,
                                  LocationCatalog.xctestDevices.id],
            policyGeneration: context.policyGeneration,
            simulatorToolchainGeneration: generations.first
        )
    }

    /// Plans a clear of the known-bloat sub-paths inside a shut-down simulator.
    static func simulatorBloat(
        for device: SimDevice,
        context: PlanningContext
    ) throws -> DeletionPlan {
        guard device.deviceSet.kind == .ordinary else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: device.name,
                reason: "Direct bloat clearing is disabled for Xcode test simulators."
            )
        }
        return try KnownBloat.createBloatDeletionPlan(
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
        guard device.deviceSet.kind == .ordinary else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: device.name,
                reason: "Use the scoped Delete Test Simulator action for this device set."
            )
        }
        let udid = try SimctlIdentifier.validatedUDID(device.udid)
        try requireRuntimeAvailabilityAuthority(for: device)
        try rejectToolchainIssue(of: device)
        try rejectProtectedDescendants(of: device, protectedPaths: context.protectedPaths)
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
        guard device.deviceSet.kind == .ordinary else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: device.name,
                reason: "Use the scoped Delete Test Simulator action for this device set."
            )
        }
        let udid = try SimctlIdentifier.validatedUDID(device.udid)
        guard device.runtimeAvailability.isConfirmedMissing else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: device.name,
                reason: "This simulator's installed runtime is not confirmed missing."
            )
        }
        try rejectToolchainIssue(of: device)
        try rejectProtectedDescendants(of: device, protectedPaths: context.protectedPaths)
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
        guard runtime.sizeIsKnown, runtime.sizeBytes > 0 else {
            throw DeletionPlanningError.runtimeToolingUnavailable(
                name: runtime.name,
                reason: "The runtime footprint could not be measured, so deletion cannot be reviewed safely."
            )
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
            reclaimableBytes: runtime.sizeBytes,
            installation: SimRuntimeInstallation(identifier: runtime.runtimeIdentifier, build: runtime.build)
        )
        // Runtime deletion also invalidates device availability.
        return DeletionPlan.plannedSingle(
            target,
            confirmLabel: "Delete Permanently",
            affectedLocationIds: [LocationCatalog.simulatorRuntimes.id, LocationCatalog.simulatorDevices.id,
                                  LocationCatalog.xctestDevices.id],
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

    private static func requireRuntimeAvailabilityAuthority(for device: SimDevice) throws {
        guard case let .unknown(reason) = device.runtimeAvailability else { return }
        throw DeletionPlanningError.runtimeToolingUnavailable(name: device.name, reason: reason)
    }
}
