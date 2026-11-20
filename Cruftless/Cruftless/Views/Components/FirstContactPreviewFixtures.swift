#if DEBUG
    import CruftlessCore
    import CruftlessFixtures
    import Foundation

    @MainActor
    extension FirstContactState {
        /// A state backed by a throwaway defaults suite, live or already retired.
        static func preview(isRetired: Bool = false) -> FirstContactState {
            let defaults = ScratchDefaults(label: "cruftless-first-contact-preview").defaults
            let store = FirstContactStore(userDefaults: defaults)
            if isRetired { store.retire(.dismissed) }
            return FirstContactState(store: store)
        }
    }
#endif
