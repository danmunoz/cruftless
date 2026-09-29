import Foundation

public enum DeletionPlanningError: Error, Sendable, Equatable, LocalizedError {
    /// Reveal-only or root-owned tier.
    case notDeletable(title: String)
    /// The scan could not read the location.
    case unavailable(title: String, reason: String)
    /// A flagged (⚠) location is never cleared as a batch.
    case flaggedLocation(title: String)
    /// The location is mutated through `simctl` only; it has no path plan.
    case simulatorLocation(title: String)
    /// The location is visible for measurement but has no supported mutation route.
    case readOnlyLocation(title: String)
    /// A Gradle cache row does not match the supported direct-child cache layout.
    case unrecognizedGradleCacheEntry(name: String)
    /// `PathGuard` refused the target.
    case refused(name: String, error: PathGuardError)
    /// The target has gone missing since the scan that showed it.
    case missingOnDisk(name: String)
    /// Nothing survived planning: the roots list was empty, or every child was flagged.
    case nothingToPlan(title: String)
    /// Two entries in one batch resolved to the same path.
    case duplicateTarget(name: String)
    /// One entry in a batch contains another.
    case nestedTargets(outer: String, inner: String)
    case simulatorNotShutdown(name: String)
    /// The runtime ships inside Xcode, so `simctl runtime delete` will refuse it.
    case runtimeNotDeletable(name: String)
    /// CoreSimulator is already removing this runtime and has not finished.
    case runtimeBeingDeleted(name: String)
    case protectedDescendantInSimulator(name: String, path: String)

    public var errorDescription: String? {
        switch self {
        case let .notDeletable(title):
            "\(title) can't be deleted by Cruftless."
        case let .unavailable(title, reason):
            "\(title) couldn't be read by the last scan: \(reason)"
        case let .flaggedLocation(title):
            "\(title) holds irreversible items and can only be cleared one at a time."
        case let .simulatorLocation(title):
            "\(title) is managed by CoreSimulator. Open it and erase or delete entries individually."
        case let .readOnlyLocation(title):
            "\(title) is read-only in Cruftless."
        case let .unrecognizedGradleCacheEntry(name):
            "\(name) is not a recognized Gradle cache directory and remains read-only."
        case let .refused(name, error):
            "\(name) can't be deleted: \(Self.describe(error))"
        case let .missingOnDisk(name):
            "\(name) is no longer where the scan found it. Rescan and try again."
        case let .nothingToPlan(title):
            "Nothing in \(title) can be cleared right now."
        case let .duplicateTarget(name):
            "\(name) is listed twice in this clear. Rescan and try again."
        case let .nestedTargets(outer, inner):
            "\(outer) already contains \(inner), so they can't be cleared in the same step."
        case let .simulatorNotShutdown(name):
            "\(name) must be shut down before its caches can be cleared."
        case let .runtimeNotDeletable(name):
            "\(name) can't be deleted: it is bundled with Xcode."
        case let .runtimeBeingDeleted(name):
            "\(name) is already being removed. It leaves this list when CoreSimulator finishes."
        case let .protectedDescendantInSimulator(name, path):
            "\(name) can't be changed: \(path) contains a path you marked as protected."
        }
    }

    private static func describe(_ error: PathGuardError) -> String {
        switch error {
        case .outsideAllowlistedRoots:
            "it is outside the folders Cruftless is allowed to clear."
        case .matchesRootItself, .notAnAllowlistedRoot:
            "it is not a folder Cruftless is allowed to clear."
        case .protectedPath:
            "it is protected."
        case .emptyOrRelativePath:
            "its path is not valid."
        case .rootHasProtectedDescendant, .containsProtectedDescendant:
            "it contains a path you marked as protected."
        case .symlinkTarget:
            "it is a symbolic link, and Cruftless only deletes real folders."
        }
    }
}
