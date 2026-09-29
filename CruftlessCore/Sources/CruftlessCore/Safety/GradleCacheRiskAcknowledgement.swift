import Foundation

/// A one-use authorization bound to the exact Gradle cache row the user acknowledged.
package final class GradleCacheRiskAcknowledgement: @unchecked Sendable, Hashable {
    private let lock = NSLock()
    private var consumed = false

    private let identity = UUID()
    private let locationID: String
    private let targetID: String
    private let targetPath: String
    private let cacheRootPath: String
    private let policyGeneration: UInt64

    package init(child: ChildEntry, cacheRoot: URL, policyGeneration: UInt64) {
        locationID = LocationCatalog.gradleCaches.id
        targetID = child.id
        targetPath = ProtectedPaths.normalize(child.url)
        cacheRootPath = ProtectedPaths.normalize(cacheRoot)
        self.policyGeneration = policyGeneration
    }

    package func consume(
        planItems: [DeletionTarget],
        affectedLocationIDs: Set<String>,
        planPolicyGeneration: UInt64
    ) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard !consumed,
              planPolicyGeneration == policyGeneration,
              affectedLocationIDs == [locationID],
              planItems.count == 1,
              matches(planItems[0])
        else { return false }
        consumed = true
        return true
    }

    package func matches(
        _ target: DeletionTarget,
        affectedLocationIDs: Set<String>,
        planPolicyGeneration: UInt64
    ) -> Bool {
        guard planPolicyGeneration == policyGeneration,
              affectedLocationIDs == [locationID]
        else { return false }
        return matches(target)
    }

    package func matches(_ target: DeletionTarget) -> Bool {
        guard case let .path(id, _, validatedPath, _, _, _, _, _) = target else { return false }
        let targetPath = ProtectedPaths.normalize(validatedPath.url)
        return id == targetID
            && targetPath == self.targetPath
            && validatedPath.allowlistedRootPaths.contains(cacheRootPath)
            && targetPath.hasPrefix(cacheRootPath + "/")
            && !targetPath.dropFirst(cacheRootPath.count + 1).contains("/")
    }

    package static func == (
        lhs: GradleCacheRiskAcknowledgement,
        rhs: GradleCacheRiskAcknowledgement
    ) -> Bool {
        lhs.identity == rhs.identity
    }

    package func hash(into hasher: inout Hasher) {
        hasher.combine(identity)
    }
}
