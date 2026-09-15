import Foundation

/// Defines paths that are strictly forbidden from being deleted.
public struct ProtectedPaths: Sendable {
    public static let `default` = ProtectedPaths()

    public let customProtectedPaths: [URL]

    private let systemProtectedPaths: Set<String>

    /// Custom paths, precomputed.
    private let customForms: [ProtectedPathForms]

    /// Paths that must never sit *strictly inside* a delete target.
    private let structuralAnchors: [ProtectedPathForms]

    private let accountHome: String?

    public init(customProtectedPaths: [URL] = []) {
        self.init(
            customProtectedPaths: customProtectedPaths,
            home: URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
        )
    }

    public init(customProtectedPaths: [URL], home: URL) {
        var seenResolved: Set<String> = []
        var uniqueURLs: [URL] = []
        var forms: [ProtectedPathForms] = []
        for url in customProtectedPaths {
            let candidate = ProtectedPathForms(url: url)
            guard seenResolved.insert(candidate.resolved).inserted else { continue }
            uniqueURLs.append(url)
            forms.append(candidate)
        }
        self.customProtectedPaths = uniqueURLs
        customForms = forms

        let homePath = PathNormalizer.normalize(home.path(percentEncoded: false))
        let account = Self.accountHomeFolder(homePath.lowercased())
        accountHome = account

        var exact: Set<String> = []
        func protectExactly(_ path: String) {
            let pathForms = ProtectedPathForms(path: path)
            exact.insert(pathForms.lexical)
            exact.insert(pathForms.resolved)
        }
        for path in Self.builtInProtectedRoots {
            protectExactly(path)
        }
        protectExactly(homePath)
        if let account {
            protectExactly(account)
        }
        for suffix in Self.protectedHomeSubdirectories {
            protectExactly((homePath as NSString).appendingPathComponent(suffix))
        }
        systemProtectedPaths = exact

        var anchors = Self.builtInProtectedRoots
            .filter { $0 != "/" }
            .map { ProtectedPathForms(path: $0) }
        anchors.append(ProtectedPathForms(path: homePath))
        for suffix in Self.protectedHomeSubdirectories + Self.anchoredHomeSubdirectories {
            anchors.append(ProtectedPathForms(path: (homePath as NSString).appendingPathComponent(suffix)))
        }
        structuralAnchors = anchors
    }

    // MARK: - Normalization

    public static func normalize(_ url: URL) -> String {
        PathNormalizer.normalize(url.path(percentEncoded: false))
    }

    /// Lexical standardization only: tilde-expanded, `..` resolved, trailing slash stripped, symlinks left alone.
    public static func standardize(_ url: URL) -> String {
        PathNormalizer.lexical(url.path(percentEncoded: false))
    }

    // MARK: - Queries

    public func isProtected(_ url: URL) -> Bool {
        // Protects every device.plist.
        if url.lastPathComponent == "device.plist" {
            return true
        }

        let forms = ProtectedPathForms(url: url)
        if (forms.resolved as NSString).lastPathComponent == "device.plist" {
            return true
        }

        if isSystemProtected(forms) {
            return true
        }

        if Self.isCoreSimulatorStructure(forms.lexical) || Self.isCoreSimulatorStructure(forms.resolved) {
            return true
        }

        return customForms.contains { $0.coversOrEquals(forms) }
    }

    public func containsProtectedDescendant(in root: URL) -> Bool {
        let forms = ProtectedPathForms(url: root)
        if customForms.contains(where: { forms.coversOrEquals($0) }) {
            return true
        }
        return containsStructuralAnchor(forms)
    }

    /// The built-in half of `containsProtectedDescendant(in:)`.
    private func containsStructuralAnchor(_ forms: ProtectedPathForms) -> Bool {
        structuralAnchors.contains { forms.strictlyContains($0) }
    }

    public func containsCustomProtectedPath(in root: URL) -> Bool {
        containsProtectedDescendant(in: root)
    }

    /// Whether `url` may serve as a `PathGuard` root at all.
    public func isUsableRoot(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let rawPath = url.path(percentEncoded: false)
        guard rawPath.hasPrefix("/"), !rawPath.contains("\0") else { return false }

        let forms = ProtectedPathForms(url: url)
        guard forms.resolved != "/", forms.lexical != "/" else { return false }
        guard !isSystemProtected(forms) else { return false }
        guard !customForms.contains(where: { $0.coversOrEquals(forms) }) else { return false }
        return !containsStructuralAnchor(forms)
    }

    // MARK: - Tables

    /// Exact paths that are protected outright.
    private static let builtInProtectedRoots = [
        "/",
        "/System",
        "/Library",
        "/Applications",
        "/bin",
        "/sbin",
        "/usr",
        "/etc",
        "/opt",
        "/var",
        "/var/db",
        "/var/log",
        "/var/root",
        "/private",
        "/Users",
        "/Volumes"
    ]

    /// Home subdirectories protected outright, and anchored.
    private static let protectedHomeSubdirectories = [
        "Library",
        "Documents",
        "Desktop",
        "Downloads"
    ]

    private static let anchoredHomeSubdirectories = [
        "Library/Developer/CoreSimulator",
        "Library/Developer/Xcode/Archives",
        "Library/Developer/Xcode/UserData",
        "Library/MobileDevice",
        "Library/Keychains",
        ".ssh"
    ]

    private static let rootRestrictedPrefixes = [
        "/system/",
        "/applications/",
        "/bin/",
        "/sbin/",
        "/usr/",
        "/library/",
        "/etc/",
        "/private/etc/",
        "/opt/",
        "/var/db/",
        "/private/var/db/",
        "/var/log/",
        "/private/var/log/",
        "/var/root/",
        "/private/var/root/"
    ]

    // MARK: - Rules

    /// The default APFS volume is case-insensitive, so `/system/library` names the same directory as `/System/Library`.
    private func isSystemProtected(_ forms: ProtectedPathForms) -> Bool {
        for spelling in forms.variants {
            if systemProtectedPaths.contains(spelling) {
                return true
            }
            if Self.rootRestrictedPrefixes.contains(where: { spelling.hasPrefix($0) }) {
                return true
            }
            if Self.isVolumeMountPoint(spelling) {
                return true
            }
            if isForeignUserPath(spelling) {
                return true
            }
        }
        return false
    }

    /// `/Volumes` and every direct child of it: a mount point: are protected as targets and as roots.
    private static func isVolumeMountPoint(_ lowered: String) -> Bool {
        guard lowered == "/volumes" || lowered.hasPrefix("/volumes/") else { return false }
        return lowered.split(separator: "/", omittingEmptySubsequences: true).count <= 2
    }

    /// Anything under `/Users` that is not this account's own folder belongs to somebody else on the machine.
    private func isForeignUserPath(_ lowered: String) -> Bool {
        guard lowered == "/users" || lowered.hasPrefix("/users/") else { return false }
        guard let accountHome else { return true }
        return !(lowered == accountHome || lowered.hasPrefix(accountHome + "/"))
    }

    private static func accountHomeFolder(_ homeLowered: String) -> String? {
        let components = homeLowered.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2, components[0] == "users" else { return nil }
        return "/users/" + components[1]
    }

    static func isCoreSimulatorStructure(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        guard components.count >= 2 else { return false }

        for index in 0 ..< (components.count - 1)
            where components[index].caseInsensitiveCompare("CoreSimulator") == .orderedSame
            && components[index + 1].caseInsensitiveCompare("Devices") == .orderedSame {
            if components.count - (index + 2) <= 2 {
                return true
            }
        }
        return false
    }
}
