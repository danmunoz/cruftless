import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("First-contact strip")
struct FirstContactStripTests {
    private func withStore(_ body: (FirstContactStore, UserDefaults) throws -> Void) throws {
        let scratch = ScratchDefaults()
        defer { TestFileSystem.remove(scratch) }
        let defaults = scratch.defaults
        try body(FirstContactStore(userDefaults: defaults), defaults)
    }

    @Test("Shows on the list and scanning screens until retired")
    func visibleOnListAndScanning() {
        #expect(FirstContactStrip.isVisible(on: .list, isRetired: false))
        #expect(FirstContactStrip.isVisible(on: .scanning, isRetired: false))
    }

    @Test("Never shows on a placeholder")
    func hiddenOnPlaceholder() {
        #expect(!FirstContactStrip.isVisible(on: .placeholder, isRetired: false))
    }

    @Test("Never shows once retired", arguments: [PopoverListScreen.list, .scanning, .placeholder])
    func hiddenWhenRetired(screen: PopoverListScreen) {
        #expect(!FirstContactStrip.isVisible(on: screen, isRetired: true))
    }

    @Test("A fresh store is live")
    func freshStore() throws {
        try withStore { store, _ in
            #expect(!store.isRetired)
            #expect(store.retirement == nil)
        }
    }

    @Test("Retiring persists across store instances", arguments: [FirstContactRetirement.dismissed, .reviewCompleted])
    func retirementPersists(reason: FirstContactRetirement) throws {
        try withStore { store, defaults in
            store.retire(reason)
            let reopened = FirstContactStore(userDefaults: defaults)
            #expect(reopened.isRetired)
            #expect(reopened.retirement == reason)
        }
    }

    @Test("The first reason wins")
    func firstReasonWins() throws {
        try withStore { store, _ in
            store.retire(.reviewCompleted)
            store.retire(.dismissed)
            #expect(store.retirement == .reviewCompleted)
        }
    }

    @Test("An unreadable stored value reads as live")
    func unknownValue() throws {
        try withStore { store, defaults in
            defaults.set("something-else", forKey: "cruftless.firstContactRetirement")
            #expect(!store.isRetired)
        }
    }
}
