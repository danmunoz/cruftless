import Foundation

/// Persists the paths the user has marked as never-delete.
public final class ProtectedPathsStore: @unchecked Sendable {
    public static let shared = ProtectedPathsStore()

    private let userDefaults: UserDefaults
    private let key = "cruftless.customProtectedPaths"
    private let lock = NSLock()

    public init(userDefaults: UserDefaults = .standard) {
        self.userDefaults = userDefaults
    }

    public func customPaths() -> [URL] {
        lock.lock()
        defer { lock.unlock() }
        return storedPaths().map { URL(fileURLWithPath: $0, isDirectory: true) }
    }

    public func addPath(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let candidate = ProtectedPathForms(url: url)
        var current = storedPaths()
        guard !current.contains(where: { ProtectedPathForms(path: $0).isSameEntry(as: candidate) }) else {
            return
        }
        current.append(ProtectedPaths.standardize(url))
        userDefaults.set(current, forKey: key)
    }

    public func removePath(_ url: URL) {
        lock.lock()
        defer { lock.unlock() }
        let candidate = ProtectedPathForms(url: url)
        let remaining = storedPaths().filter { !ProtectedPathForms(path: $0).isSameEntry(as: candidate) }
        userDefaults.set(remaining, forKey: key)
    }

    public func protectedPaths() -> ProtectedPaths {
        ProtectedPaths(customProtectedPaths: customPaths())
    }

    private func storedPaths() -> [String] {
        let strings = userDefaults.stringArray(forKey: key) ?? []
        var seen: Set<String> = []
        var unique: [String] = []
        for stored in strings {
            let forms = ProtectedPathForms(path: stored)
            guard !forms.lexical.isEmpty, seen.insert(forms.resolved).inserted else { continue }
            unique.append(ProtectedPaths.standardize(URL(fileURLWithPath: stored, isDirectory: true)))
        }
        return unique
    }
}

private extension ProtectedPathForms {
    func isSameEntry(as other: ProtectedPathForms) -> Bool {
        lexical == other.lexical || resolved == other.resolved
    }
}
