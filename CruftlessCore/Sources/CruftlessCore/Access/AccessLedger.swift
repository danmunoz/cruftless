import Foundation

/// Persists which protected areas macOS has already asked the user about.
public final class AccessLedger: @unchecked Sendable {
    public static let shared = AccessLedger()

    private let userDefaults: UserDefaults
    private let key = "cruftless.accessAskedAreas"
    private let lock = NSLock()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func hasAsked(_ area: ProtectedArea) -> Bool {
        askedAreas().contains(area)
    }

    public func askedAreas() -> Set<ProtectedArea> {
        lock.lock()
        defer { lock.unlock() }
        return storedAreas()
    }

    public func markAsked(_ area: ProtectedArea) {
        lock.lock()
        defer { lock.unlock() }
        var areas = storedAreas()
        guard areas.insert(area).inserted else { return }
        userDefaults.set(areas.map(\.rawValue).sorted(), forKey: key)
    }

    /// Forgets an area, for an ask that never reached macOS.
    public func clearAsked(_ area: ProtectedArea) {
        lock.lock()
        defer { lock.unlock() }
        var areas = storedAreas()
        guard areas.remove(area) != nil else { return }
        userDefaults.set(areas.map(\.rawValue).sorted(), forKey: key)
    }

    private func storedAreas() -> Set<ProtectedArea> {
        Set((userDefaults.stringArray(forKey: key) ?? []).compactMap(ProtectedArea.init(rawValue:)))
    }
}
