import Foundation

// MARK: - Custom-location policy

extension RootResolver {
    /// Everything the custom-location policy is allowed to consult.
    public struct RootPolicy: Sendable {
        public let home: URL
        /// Roots of the other tracked locations.
        public let otherTrackedRoots: [URL]
        public let protectedPaths: ProtectedPaths

        public init(home: URL, otherTrackedRoots: [URL], protectedPaths: ProtectedPaths) {
            self.home = home
            self.otherTrackedRoots = otherTrackedRoots
            self.protectedPaths = protectedPaths
        }

        /// The policy the app runs with: the real tracked roots and the user's own protected paths.
        public static func standard(home: URL, protectedPaths: ProtectedPaths = .default) -> RootPolicy {
            RootPolicy(
                home: home,
                otherTrackedRoots: RootResolver.fixedTrackedRoots(home: home),
                protectedPaths: protectedPaths
            )
        }
    }

    /// Decides whether a configured location may be used as a `PathGuard` root.
    public static func customRoot(
        preferenceKey: String,
        preference value: String?,
        fallback: URL,
        policy: RootPolicy
    ) -> (root: URL, issue: RootPreferenceIssue?) {
        guard let value else { return (fallback, nil) }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return (fallback, nil) }

        let expanded = (trimmed as NSString).expandingTildeInPath
        guard expanded.hasPrefix("/") else {
            return (fallback, RootPreferenceIssue(preferenceKey: preferenceKey, value: value, reason: .notAbsolute))
        }

        let candidatePath = PathNormalizer.normalize(expanded)
        if let reason = refusalReason(for: candidatePath, fallback: fallback, policy: policy) {
            return (fallback, RootPreferenceIssue(preferenceKey: preferenceKey, value: value, reason: reason))
        }
        return (URL(fileURLWithPath: candidatePath, isDirectory: true), nil)
    }

    /// The rule the configured location trips, or `nil` when it is usable.
    private static func refusalReason(
        for candidatePath: String,
        fallback: URL,
        policy: RootPolicy
    ) -> RootPreferenceIssue.Reason? {
        guard candidatePath != "/" else { return .filesystemRoot }

        let homePath = ProtectedPaths.normalize(policy.home)
        if candidatePath == homePath || homePath.hasPrefix(candidatePath + "/") {
            return .containsHomeFolder
        }

        let candidate = URL(fileURLWithPath: candidatePath, isDirectory: true)
        guard policy.protectedPaths.isUsableRoot(candidate) else { return .protectedLocation }

        let fallbackPath = ProtectedPaths.normalize(fallback)
        guard candidatePath != fallbackPath else { return nil }
        let overlaps = policy.otherTrackedRoots
            .map(ProtectedPaths.normalize)
            .filter { $0 != fallbackPath }
            .contains { other in
                candidatePath == other
                    || candidatePath.hasPrefix(other + "/")
                    || other.hasPrefix(candidatePath + "/")
            }
        return overlaps ? .overlapsTrackedLocation : nil
    }
}
