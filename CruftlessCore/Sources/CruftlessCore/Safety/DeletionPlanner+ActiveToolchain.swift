import Foundation

extension DeletionPlanner {
    static let activeToolchainWarning =
        "This is the toolchain Xcode is currently set to use. Builds fail until you pick another under " +
            "Xcode ▸ Toolchains. "

    static func toolchainAwareConsequence(
        base: String,
        location: TrackedLocation,
        targetURL: URL?,
        activeToolchainOverrideIdentifier: String?
    ) -> String {
        guard location.id == LocationCatalog.toolchains.id,
              let targetURL,
              isActiveToolchainTarget(targetURL, overrideIdentifier: activeToolchainOverrideIdentifier)
        else {
            return base
        }
        return activeToolchainWarning + base
    }

    static func isActiveToolchainTarget(_ url: URL, overrideIdentifier: String?) -> Bool {
        guard overrideIdentifier != nil else { return false }
        if url.pathExtension == "xctoolchain" {
            return ActiveToolchain.isActive(url, overrideIdentifier: overrideIdentifier)
        }
        guard let children = try? FileManager.default.contentsOfDirectory(
            at: url,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else {
            return false
        }
        return children.contains { candidate in
            candidate.pathExtension == "xctoolchain" &&
                ActiveToolchain.isActive(candidate, overrideIdentifier: overrideIdentifier)
        }
    }
}
