import CruftlessCore
import Foundation
import Testing

@Suite("Cleanup selection")
struct CleanupSelectionTests {
    private let items = [
        CleanupSelectionItem(id: "one", reclaimableBytes: 100, groupID: "a", isSelectable: true),
        CleanupSelectionItem(id: "two", reclaimableBytes: 250, groupID: "a", isSelectable: true),
        CleanupSelectionItem(id: "three", reclaimableBytes: 500, groupID: "b", isSelectable: true),
        CleanupSelectionItem(id: "flagged", reclaimableBytes: 900, groupID: "b", isSelectable: false, disabledReason: "Flagged"),
        CleanupSelectionItem(id: "readonly", reclaimableBytes: 900, isSelectable: false, disabledReason: "Read-only")
    ]

    @Test("Group selection counts only eligible rows and calculates allocated estimate")
    func groupSelection() {
        var selection = CleanupSelection()
        selection.selectEligible(in: items, groupID: "a")
        selection.toggle("flagged", among: items)

        let resolution = selection.resolution(in: items)
        #expect(selection.selectedIDs == ["one", "two"])
        #expect(resolution.selectedCount == 2)
        #expect(resolution.estimatedBytes == 350)
        #expect(resolution.isValid)
    }

    @Test("Select all and group selection do not select disabled or future rows")
    func selectEligibleDoesNotSelectDisabledOrFutureRows() {
        var selection = CleanupSelection()
        selection.selectEligible(in: items)
        let refreshed = items + [CleanupSelectionItem(id: "future", reclaimableBytes: 700, isSelectable: true)]

        #expect(selection.selectedIDs == ["one", "two", "three"])
        #expect(selection.resolution(in: refreshed).estimatedBytes == 850)
        #expect(!selection.selectedIDs.contains("future"))
    }

    @Test("Missing, duplicated, and newly disabled selected identities invalidate the set")
    func invalidatedSelectionIsNotShrunk() {
        let selection = CleanupSelection(selectedIDs: ["one", "two"])
        let refreshed = [
            CleanupSelectionItem(id: "one", reclaimableBytes: 100, isSelectable: true),
            CleanupSelectionItem(id: "one", reclaimableBytes: 100, isSelectable: true),
            CleanupSelectionItem(id: "two", reclaimableBytes: 250, isSelectable: false, disabledReason: "Protected")
        ]

        let resolution = selection.resolution(in: refreshed)
        #expect(selection.selectedIDs == ["one", "two"])
        #expect(resolution.invalidIDs == ["one", "two"])
        #expect(!resolution.isValid)
    }

    @Test("Single-entry mode replaces selection and keeps newly selected identity exact")
    func singleEntryMode() {
        var selection = CleanupSelection()
        selection.selectOnly("one", among: items)
        selection.toggle("two", among: items, allowsMultiple: false)
        #expect(selection.selectedIDs == ["two"])
    }

    @Test("Clearing selection removes all identities")
    func clearingSelection() {
        var selection = CleanupSelection(selectedIDs: ["one", "two"])
        selection.clear()
        #expect(selection.isEmpty)
    }

    @Test("An invalid selected row can be explicitly unchecked")
    func invalidRowCanBeUnchecked() {
        var selection = CleanupSelection(selectedIDs: ["one"])
        let disabled = [CleanupSelectionItem(id: "one", reclaimableBytes: 100, isSelectable: false)]
        selection.toggle("one", among: disabled)
        #expect(selection.isEmpty)
    }
}
