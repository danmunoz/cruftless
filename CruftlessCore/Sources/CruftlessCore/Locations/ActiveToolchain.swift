import Foundation

public enum ActiveToolchain: Sendable {
    /// Xcode's preference domain.
    private static let overrideKey = "DVTDefaultToolchainOverrideIdentifer"

    public static func overrideIdentifier(
        defaults: UserDefaults = UserDefaults(suiteName: "com.apple.dt.Xcode") ?? .standard
    ) -> String? {
        guard let raw = defaults.string(forKey: overrideKey),
              !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return nil
        }
        return raw
    }

    /// Reads `CFBundleIdentifier` out of a `.xctoolchain` bundle's `Info.plist` directly: no subprocess.
    public static func identifier(ofToolchainAt url: URL) -> String? {
        let infoPlistURL = url.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: infoPlistURL) else { return nil }
        guard
            let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
            let identifier = plist["CFBundleIdentifier"] as? String
        else {
            return nil
        }
        return identifier
    }

    /// True when `url` is the toolchain bundle Xcode is currently set to use.
    public static func isActive(_ url: URL, overrideIdentifier: String?) -> Bool {
        guard let overrideIdentifier else { return false }
        guard let identifier = identifier(ofToolchainAt: url) else { return false }
        return identifier == overrideIdentifier
    }
}
