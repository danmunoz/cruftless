import Foundation

/// The app's version, read from the bundle that was actually built: the one source of truth for it.
public enum CruftlessVersion: Sendable {
    public static let shortVersionKey = "CFBundleShortVersionString"
    public static let buildKey = "CFBundleVersion"

    public static func shortVersion(from bundle: Bundle = .main) -> String? {
        (bundle.object(forInfoDictionaryKey: shortVersionKey) as? String)?
            .trimmingCharacters(in: .whitespaces)
            .nilIfEmpty
    }

    /// `"Version 1.2 (34)"`, or `"Version 1.2"` when the build number is absent or duplicates the short version.
    public static func display(from bundle: Bundle = .main) -> String? {
        display(
            shortVersion: shortVersion(from: bundle),
            build: bundle.object(forInfoDictionaryKey: buildKey) as? String
        )
    }

    static func display(shortVersion: String?, build: String?) -> String? {
        let short = shortVersion?.trimmingCharacters(in: .whitespaces).nilIfEmpty
        let build = build?.trimmingCharacters(in: .whitespaces).nilIfEmpty

        guard let short else {
            return build.map { "Version \($0)" }
        }
        guard let build, build != short else {
            return "Version \(short)"
        }
        return "Version \(short) (\(build))"
    }
}

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
