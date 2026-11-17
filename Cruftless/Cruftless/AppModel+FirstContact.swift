import CruftlessCore
import Foundation
import Observation

/// Observable mirror of the persisted first-contact strip state.
@MainActor
@Observable
public final class FirstContactState {
    public private(set) var isRetired: Bool
    private let store: FirstContactStore

    public init(store: FirstContactStore = FirstContactStore()) {
        self.store = store
        isRetired = store.isRetired
    }

    func retire(_ reason: FirstContactRetirement) {
        guard !isRetired else { return }
        store.retire(reason)
        isRetired = true
    }
}

public extension AppModel {
    func showsFirstContactStrip(on screen: PopoverListScreen) -> Bool {
        FirstContactStrip.isVisible(on: screen, isRetired: firstContact.isRetired)
    }

    func dismissFirstContactStrip() {
        firstContact.retire(.dismissed)
    }

    /// Called when the user confirms a Review, which retires the strip for good.
    func recordReviewCompleted() {
        firstContact.retire(.reviewCompleted)
    }
}
