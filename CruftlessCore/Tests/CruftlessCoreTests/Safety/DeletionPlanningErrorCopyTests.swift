import CruftlessCore
import Testing

@Suite("DeletionPlanningError copy")
struct DeletionPlanningErrorCopyTests {
    @Test("Deletion in progress explains the refusal")
    func deletionInProgressHasCopy() {
        let text = DeletionPlanningError.deletionInProgress.errorDescription
        #expect(text?.isEmpty == false)
    }

    @Test("Inventory changed names the location")
    func inventoryChangedMentionsTitle() {
        let text = DeletionPlanningError.inventoryChanged(title: "Derived Data").errorDescription
        #expect(text?.contains("Derived Data") == true)
    }
}
