#if DEBUG
    import Foundation

    /// A throwaway defaults suite backed by a plist in the temporary directory, never in `~/Library/Preferences`.
    public struct ScratchDefaults {
        public let defaults: UserDefaults
        /// The suite name, an absolute path that CFPreferences stores as `<suiteName>.plist`.
        public let suiteName: String
        /// The plist file backing the suite.
        public let fileURL: URL

        public init(label: String = "cruftless-defaults") {
            let base = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
                .appendingPathComponent("\(label)-\(UUID().uuidString)")
            suiteName = base.path(percentEncoded: false)
            fileURL = base.appendingPathExtension("plist")
            guard let defaults = UserDefaults(suiteName: suiteName) else {
                preconditionFailure("UserDefaults refused scratch suite \(suiteName)")
            }
            self.defaults = defaults
        }
    }
#endif
