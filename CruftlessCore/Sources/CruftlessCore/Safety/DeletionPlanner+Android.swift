import Foundation

public extension DeletionPlanner {
    static func androidAVD(_ request: AndroidAVDRemovalRequest, context: PlanningContext) throws -> DeletionPlan {
        do {
            try request.identity.revalidate(protectedPaths: context.protectedPaths)
        } catch {
            throw DeletionPlanningError.unavailable(title: request.displayName, reason: error.localizedDescription)
        }
        return .plannedSingle(.androidAVDDelete(request), confirmLabel: "Delete Device",
                              affectedLocationIds: [LocationCatalog.androidAVDs.id], policyGeneration: context.policyGeneration)
    }
}
