import Foundation

/// A validated, review-ready plan representing one or more deletion targets.
public struct DeletionPlan: Sendable, Hashable {
    public let items: [DeletionTarget]
    public let confirmLabel: String
    /// Tracked locations affected by execution.
    public let affectedLocationIds: Set<String>
    public let policyGeneration: UInt64
    /// Toolchain snapshot used by simulator listings in this plan.
    public let simulatorToolchainGeneration: UUID?
    package let isPlannerAuthorized: Bool
    package let gradleCacheRiskAcknowledgement: GradleCacheRiskAcknowledgement?

    public var totalReclaimableBytes: Int64 {
        items.reduce(0) { $0 + $1.reclaimableBytes }
    }

    public var isEmpty: Bool {
        items.isEmpty
    }

    public var count: Int {
        items.count
    }

    public var hasFlaggedItem: Bool {
        items.contains { $0.isFlagged }
    }

    /// Rescan scope derived from affected locations.
    public var rescanScope: InvalidationScope {
        affectedLocationIds.isEmpty ? .everything : .locations(affectedLocationIds)
    }

    init(
        items: [DeletionTarget],
        confirmLabel: String = "Delete Permanently",
        affectedLocationIds: Set<String> = [],
        policyGeneration: UInt64 = 0,
        simulatorToolchainGeneration: UUID? = nil,
        isPlannerAuthorized: Bool = false,
        gradleCacheRiskAcknowledgement: GradleCacheRiskAcknowledgement? = nil
    ) {
        self.items = items
        self.confirmLabel = confirmLabel
        self.affectedLocationIds = affectedLocationIds
        self.policyGeneration = policyGeneration
        self.simulatorToolchainGeneration = simulatorToolchainGeneration
        self.isPlannerAuthorized = isPlannerAuthorized
        self.gradleCacheRiskAcknowledgement = gradleCacheRiskAcknowledgement
    }

    /// Creates a plan for a single explicitly chosen target (supports flagged items).
    public static func single(
        _ target: DeletionTarget,
        confirmLabel: String? = nil,
        affectedLocationIds: Set<String> = [],
        policyGeneration: UInt64 = 0,
        simulatorToolchainGeneration: UUID? = nil
    ) -> DeletionPlan {
        let label: String = if let explicitLabel = confirmLabel {
            explicitLabel
        } else {
            switch target {
            case .simulatorErase:
                "Shut Down and Erase"
            case .path, .simulatorDelete, .runtimeDelete:
                "Delete Permanently"
            }
        }
        return DeletionPlan(
            items: [target],
            confirmLabel: label,
            affectedLocationIds: affectedLocationIds,
            policyGeneration: policyGeneration,
            simulatorToolchainGeneration: simulatorToolchainGeneration
        )
    }

    /// Creates a batch plan, strictly excluding any flagged (⚠) entries.
    public static func batch(
        _ targets: [DeletionTarget],
        confirmLabel: String = "Delete Permanently",
        affectedLocationIds: Set<String> = [],
        policyGeneration: UInt64 = 0
    ) -> DeletionPlan {
        let unflagged = targets.filter { !$0.isFlagged }
        return DeletionPlan(
            items: unflagged,
            confirmLabel: confirmLabel,
            affectedLocationIds: affectedLocationIds,
            policyGeneration: policyGeneration
        )
    }

    package static func plannedSingle(
        _ target: DeletionTarget,
        confirmLabel: String? = nil,
        affectedLocationIds: Set<String> = [],
        policyGeneration: UInt64 = 0,
        simulatorToolchainGeneration: UUID? = nil,
        gradleCacheRiskAcknowledgement: GradleCacheRiskAcknowledgement? = nil
    ) -> DeletionPlan {
        let plan = single(
            target,
            confirmLabel: confirmLabel,
            affectedLocationIds: affectedLocationIds,
            policyGeneration: policyGeneration,
            simulatorToolchainGeneration: simulatorToolchainGeneration
        )
        return DeletionPlan(
            items: plan.items,
            confirmLabel: plan.confirmLabel,
            affectedLocationIds: affectedLocationIds,
            policyGeneration: policyGeneration,
            simulatorToolchainGeneration: simulatorToolchainGeneration,
            isPlannerAuthorized: true,
            gradleCacheRiskAcknowledgement: gradleCacheRiskAcknowledgement
        )
    }

    package static func plannedBatch(
        _ targets: [DeletionTarget],
        confirmLabel: String = "Delete Permanently",
        affectedLocationIds: Set<String> = [],
        policyGeneration: UInt64 = 0
    ) -> DeletionPlan {
        let plan = batch(
            targets,
            confirmLabel: confirmLabel,
            affectedLocationIds: affectedLocationIds,
            policyGeneration: policyGeneration
        )
        return DeletionPlan(
            items: plan.items,
            confirmLabel: plan.confirmLabel,
            affectedLocationIds: affectedLocationIds,
            policyGeneration: policyGeneration,
            isPlannerAuthorized: true
        )
    }
}
