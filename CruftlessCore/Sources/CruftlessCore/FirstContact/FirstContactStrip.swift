import Foundation

/// Which body the popover's List screen is drawing.
public enum PopoverListScreen: Sendable, Equatable {
    /// Inventory rows.
    case list
    /// A scan the user is watching, before any rows exist.
    case scanning
    /// Any centred placeholder: nothing scanned, nothing to reclaim, scan failed.
    case placeholder
}

/// Why the first-contact strip stopped showing.
public enum FirstContactRetirement: String, Sendable, Equatable {
    case dismissed
    case reviewCompleted
}

/// Decides whether the popover shows its one-time safety strip.
public enum FirstContactStrip {
    public static let message = "Every deletion is reviewed first. Nothing happens until you choose."

    public static func isVisible(on screen: PopoverListScreen, isRetired: Bool) -> Bool {
        guard !isRetired else { return false }
        switch screen {
        case .list, .scanning: return true
        case .placeholder: return false
        }
    }
}

/// Persists that the first-contact strip is retired, so it never returns.
public final class FirstContactStore: @unchecked Sendable {
    private let userDefaults: UserDefaults
    private let key = "cruftless.firstContactRetirement"
    private let lock = NSLock()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public var isRetired: Bool {
        retirement != nil
    }

    /// The first reason recorded, or nil while the strip is still live.
    public var retirement: FirstContactRetirement? {
        lock.lock()
        defer { lock.unlock() }
        return userDefaults.string(forKey: key).flatMap(FirstContactRetirement.init(rawValue:))
    }

    /// Records the first retirement; later calls keep the original reason.
    public func retire(_ reason: FirstContactRetirement) {
        lock.lock()
        defer { lock.unlock() }
        guard userDefaults.string(forKey: key).flatMap(FirstContactRetirement.init(rawValue:)) == nil else { return }
        userDefaults.set(reason.rawValue, forKey: key)
    }
}
