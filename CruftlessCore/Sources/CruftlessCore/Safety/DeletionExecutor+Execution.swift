import Foundation

extension DeletionExecutor {
    /// Executes all items in the plan sequentially, collecting per-item outcomes.
    public func execute(
        _ plan: DeletionPlan,
        onProgress: (@Sendable (DeletionProgress) -> Void)? = nil
    ) async -> DeletionResult {
        if plan.items.contains(where: { $0.validatedPath != nil }), !plan.isPlannerAuthorized {
            return Self.refusedAsUnverified(plan)
        }
        guard let admission = admissionScope(for: plan) else {
            return Self.refusedAsUnverified(plan)
        }
        let admitted = policyGenerationAuthority.withCurrentGeneration(
            plan.policyGeneration,
            affectedLocationIDs: admission.locationIDs
        ) {
            guard !isExecuting else { return false }
            isExecuting = true
            return true
        }
        guard let admitted else { return Self.refusedForPolicyChange(plan) }
        guard admitted else { return Self.refusedAsConcurrent(plan) }
        let hasSimulatorMutation = plan.items.contains(where: Self.isSimulatorMutation)
        if hasSimulatorMutation,
           !(await simulatorExecutor.beginToolchainOperation(generation: plan.simulatorToolchainGeneration)) {
            isExecuting = false
            return Self.refusedForToolchainChange(plan)
        }
        self.onProgress = onProgress
        defer {
            isExecuting = false
            self.onProgress = nil
        }

        return await executeItems(plan, admission: admission, hasSimulatorMutation: hasSimulatorMutation)
    }

    private func executeItems(
        _ plan: DeletionPlan,
        admission: (locationIDs: Set<String>, gradleAcknowledgement: GradleCacheRiskAcknowledgement?),
        hasSimulatorMutation: Bool
    ) async -> DeletionResult {
        var outcomes: [ItemOutcome] = []
        outcomes.reserveCapacity(plan.items.count)
        for (index, item) in plan.items.enumerated() {
            guard plan.policyGeneration == policyGenerationAuthority.currentGeneration else {
                outcomes.append(contentsOf: plan.items[index...].map {
                    ItemOutcome(target: $0, status: .notAttempted(reason: .policyChanged), freedBytes: 0)
                })
                break
            }
            if Task.isCancelled {
                outcomes.append(ItemOutcome(target: item, status: .notAttempted(reason: .cancelled), freedBytes: 0))
                continue
            }
            outcomes.append(await executeSingle(
                item,
                affectedLocationIds: plan.affectedLocationIds,
                policyGeneration: plan.policyGeneration,
                gradleCacheRiskAcknowledgement: admission.gradleAcknowledgement
            ))
        }
        if hasSimulatorMutation {
            await simulatorExecutor.endToolchainOperation(generation: plan.simulatorToolchainGeneration)
        }
        return DeletionResult(items: outcomes)
    }

    private static func isSimulatorMutation(_ target: DeletionTarget) -> Bool {
        switch target {
        case .simulatorErase, .simulatorDelete, .runtimeDelete: true
        case .path: false
        }
    }

    private func admissionScope(
        for plan: DeletionPlan
    ) -> (locationIDs: Set<String>, gradleAcknowledgement: GradleCacheRiskAcknowledgement?)? {
        let acknowledgement = plan.gradleCacheRiskAcknowledgement
        if let acknowledgement,
           !acknowledgement.consume(
               planItems: plan.items,
               affectedLocationIDs: plan.affectedLocationIds,
               planPolicyGeneration: plan.policyGeneration
           ) {
            return nil
        }
        let authorizedIDs: Set<String> = acknowledgement == nil
            ? []
            : [LocationCatalog.gradleCaches.id]
        let locationIDs = plan.affectedLocationIds.subtracting(authorizedIDs).union(
            policyGenerationAuthority.readOnlyLocationIDs(matching: plan.items)
                .subtracting(authorizedIDs)
        )
        return (locationIDs, acknowledgement)
    }
}
