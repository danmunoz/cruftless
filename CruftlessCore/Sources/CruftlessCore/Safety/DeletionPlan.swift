import Foundation

/// A validated, review-ready plan representing one or more deletion targets.
public struct DeletionPlan: Sendable, Hashable {
    public let items: [DeletionTarget]
    public let confirmLabel: String

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

    init(items: [DeletionTarget], confirmLabel: String = "Delete Permanently") {
        self.items = items
        self.confirmLabel = confirmLabel
    }

    /// Creates a plan for a single explicitly chosen target (supports flagged items).
    public static func single(_ target: DeletionTarget, confirmLabel: String? = nil) -> DeletionPlan {
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
        return DeletionPlan(items: [target], confirmLabel: label)
    }

    /// Creates a batch plan, strictly excluding any flagged (⚠) entries.
    public static func batch(_ targets: [DeletionTarget], confirmLabel: String = "Delete Permanently") -> DeletionPlan {
        let unflagged = targets.filter { !$0.isFlagged }
        return DeletionPlan(items: unflagged, confirmLabel: confirmLabel)
    }
}
