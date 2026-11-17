#if DEBUG
    import CruftlessCore
    import Foundation

    @MainActor
    extension FirstContactState {
        /// A state backed by a throwaway defaults suite, live or already retired.
        static func preview(isRetired: Bool = false) -> FirstContactState {
            let defaults = UserDefaults(suiteName: "Cruftless.FirstContactPreview.\(UUID().uuidString)")!
            let store = FirstContactStore(userDefaults: defaults)
            if isRetired { store.retire(.dismissed) }
            return FirstContactState(store: store)
        }
    }
#endif
