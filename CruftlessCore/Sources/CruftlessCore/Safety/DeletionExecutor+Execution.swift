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
        let admissionIDs = plan.affectedLocationIds.union(
            policyGenerationAuthority.readOnlyLocationIDs(matching: plan.items)
        )
        let admitted = policyGenerationAuthority.withCurrentGeneration(
            plan.policyGeneration,
            affectedLocationIDs: admissionIDs
        ) {
            guard !isExecuting else { return false }
            isExecuting = true
            return true
        }
        guard let admitted else { return Self.refusedForPolicyChange(plan) }
        guard admitted else { return Self.refusedAsConcurrent(plan) }
        self.onProgress = onProgress
        defer {
            isExecuting = false
            self.onProgress = nil
        }

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
            outcomes.append(await executeSingle(item, affectedLocationIds: plan.affectedLocationIds))
        }
        return DeletionResult(items: outcomes)
    }
}
