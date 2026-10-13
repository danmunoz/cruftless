import Foundation

/// A stable row identity and current eligibility snapshot for cleanup selection.
public struct CleanupSelectionItem: Sendable, Hashable, Identifiable {
    public let id: String
    public let reclaimableBytes: Int64
    public let groupID: String?
    public let isSelectable: Bool
    public let disabledReason: String?

    public init(
        id: String,
        reclaimableBytes: Int64,
        groupID: String? = nil,
        isSelectable: Bool,
        disabledReason: String? = nil
    ) {
        self.id = id
        self.reclaimableBytes = max(0, reclaimableBytes)
        self.groupID = groupID
        self.isSelectable = isSelectable
        self.disabledReason = disabledReason
    }
}

/// Selection state keeps identities that disappear during refresh so a reviewed set never shrinks silently.
public struct CleanupSelection: Sendable, Equatable {
    public private(set) var selectedIDs: Set<String> = []

    public init(selectedIDs: Set<String> = []) {
        self.selectedIDs = selectedIDs
    }

    public var count: Int { selectedIDs.count }
    public var isEmpty: Bool { selectedIDs.isEmpty }

    public mutating func toggle(_ id: String, among items: [CleanupSelectionItem], allowsMultiple: Bool = true) {
        if selectedIDs.contains(id) {
            selectedIDs.remove(id)
            return
        }
        guard items.first(where: { $0.id == id })?.isSelectable == true else { return }
        if allowsMultiple {
            selectedIDs.insert(id)
        } else {
            selectedIDs = [id]
        }
    }

    public mutating func selectEligible(in items: [CleanupSelectionItem], groupID: String? = nil) {
        let eligible = items.filter { item in
            item.isSelectable && (groupID == nil || item.groupID == groupID)
        }
        selectedIDs.formUnion(eligible.map(\.id))
    }

    public mutating func selectOnly(_ id: String, among items: [CleanupSelectionItem]) {
        guard items.first(where: { $0.id == id })?.isSelectable == true else { return }
        selectedIDs = [id]
    }

    public mutating func clear() {
        selectedIDs.removeAll()
    }

    public func resolution(in items: [CleanupSelectionItem]) -> CleanupSelectionResolution {
        let grouped = Dictionary(grouping: items, by: \.id)
        var bytes: Int64 = 0
        var invalid: Set<String> = []
        for id in selectedIDs {
            guard let matches = grouped[id], matches.count == 1,
                  let item = matches.first, item.isSelectable
            else {
                invalid.insert(id)
                continue
            }
            bytes += item.reclaimableBytes
        }
        return CleanupSelectionResolution(
            selectedCount: selectedIDs.count,
            estimatedBytes: bytes,
            invalidIDs: invalid
        )
    }
}

public struct CleanupSelectionResolution: Sendable, Equatable {
    public let selectedCount: Int
    public let estimatedBytes: Int64
    public let invalidIDs: Set<String>

    public var isValid: Bool { selectedCount > 0 && invalidIDs.isEmpty }
}
