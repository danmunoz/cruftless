import Foundation

extension DeletionExecutor {
    static func refusedAsUnverified(_ plan: DeletionPlan) -> DeletionResult {
        DeletionResult(
            items: plan.items.map {
                ItemOutcome(target: $0, status: .notAttempted(reason: .unverifiedPlan), freedBytes: 0)
            }
        )
    }

    static func refusedAsConcurrent(_ plan: DeletionPlan) -> DeletionResult {
        DeletionResult(
            items: plan.items.map {
                ItemOutcome(target: $0, status: .notAttempted(reason: .executorBusy), freedBytes: 0)
            }
        )
    }

    static func refusedForPolicyChange(_ plan: DeletionPlan) -> DeletionResult {
        DeletionResult(
            items: plan.items.map {
                ItemOutcome(target: $0, status: .notAttempted(reason: .policyChanged), freedBytes: 0)
            }
        )
    }

    static func refusedForToolchainChange(_ plan: DeletionPlan) -> DeletionResult {
        DeletionResult(
            items: plan.items.map {
                ItemOutcome(target: $0, status: .notAttempted(reason: .toolchainChanged), freedBytes: 0)
            }
        )
    }
}
