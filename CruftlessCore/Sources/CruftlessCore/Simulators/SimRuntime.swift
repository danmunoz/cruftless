import Foundation

/// Represents an installed CoreSimulator runtime disk image or cryptex.
public struct SimRuntime: Sendable, Hashable, Identifiable {
    public var id: String {
        identifier
    }

    public let identifier: String
    public let runtimeIdentifier: String
    public let name: String
    public let build: String
    public let sizeBytes: Int64
    public let isDeletable: Bool
    /// What CoreSimulator says this runtime is currently doing.
    public let state: SimRuntimeState

    public init(
        identifier: String,
        runtimeIdentifier: String,
        name: String,
        build: String,
        sizeBytes: Int64,
        isDeletable: Bool,
        state: SimRuntimeState = .unreported
    ) {
        self.identifier = identifier
        self.runtimeIdentifier = runtimeIdentifier
        self.name = name
        self.build = build
        self.sizeBytes = sizeBytes
        self.isDeletable = isDeletable
        self.state = state
    }

    public var canPlanDelete: Bool {
        isDeletable && !state.isBeingDeleted
    }
}
