import Foundation

/// Everything `DeletionPlanner` needs that is not the thing being planned.
public struct PlanningContext: Sendable {
    /// The paths the user marked as never-delete, plus the built-in denylist.
    public let protectedPaths: ProtectedPaths

    /// The toolchain Xcode is currently set to use, or `nil` when it is on its bundled default.
    public let activeToolchainOverrideIdentifier: String?
    public let policyGeneration: UInt64

    public let childrenProvider: @Sendable (TrackedLocation) -> [ChildEntry]

    public init(
        protectedPaths: ProtectedPaths = .default,
        activeToolchainOverrideIdentifier: String? = nil,
        policyGeneration: UInt64 = 0,
        childrenProvider: @escaping @Sendable (TrackedLocation) -> [ChildEntry] = {
            DrillDownProvider.loadChildren(for: $0)
        }
    ) {
        self.protectedPaths = protectedPaths
        self.activeToolchainOverrideIdentifier = activeToolchainOverrideIdentifier
        self.policyGeneration = policyGeneration
        self.childrenProvider = childrenProvider
    }

    public static func live(protectedPaths: ProtectedPaths, policyGeneration: UInt64 = 0) -> PlanningContext {
        PlanningContext(
            protectedPaths: protectedPaths,
            activeToolchainOverrideIdentifier: ActiveToolchain.overrideIdentifier(),
            policyGeneration: policyGeneration
        )
    }

    public func withChildren(
        _ provider: @escaping @Sendable (TrackedLocation) -> [ChildEntry]
    ) -> PlanningContext {
        PlanningContext(
            protectedPaths: protectedPaths,
            activeToolchainOverrideIdentifier: activeToolchainOverrideIdentifier,
            policyGeneration: policyGeneration,
            childrenProvider: provider
        )
    }
}
