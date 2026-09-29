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

    private let androidProtectedPrefixes: [String]
    private let gradleUserHomePrefixes: [String]

    private let accountHome: String?
    private let homePath: String
    private let hasUnresolvedAndroidRedirects: Bool

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
        self.homePath = homePath.lowercased()
        hasUnresolvedAndroidRedirects = RootResolver.hasUnresolvedAndroidRedirectMetadata(home: home)
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
        let androidPrefixes = Self.androidProtectedPrefixes(home: home, homePath: homePath)
        let gradlePrefixes = Self.gradleUserHomePrefixes(homePath: homePath)
        for path in androidPrefixes {
            let forms = ProtectedPathForms(path: path)
            exact.insert(forms.lexical)
            exact.insert(forms.resolved)
        }
        systemProtectedPaths = exact
        androidProtectedPrefixes = androidPrefixes.map { PathNormalizer.lexical($0).lowercased() }
        gradleUserHomePrefixes = gradlePrefixes.map { PathNormalizer.lexical($0).lowercased() }

        structuralAnchors = Self.protectedAnchors(
            homePath: homePath,
            androidPrefixes: androidPrefixes,
            gradlePrefixes: gradlePrefixes
        )
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

    /// Whether a user-protected path is the target, an ancestor, or a descendant of it.
    public func intersectsCustomProtection(_ url: URL) -> Bool {
        let forms = ProtectedPathForms(url: url)
        return customForms.contains { $0.coversOrEquals(forms) || forms.coversOrEquals($0) }
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

    /// Whether the normal Gradle-home denylist is the only built-in rule covering this cache entry.
    package func allowsGradleCacheEntry(_ target: URL, under cacheRoot: URL) -> Bool {
        guard !intersectsCustomProtection(target) else { return false }
        let forms = ProtectedPathForms(url: target)
        guard !isSystemProtected(forms, allowingGradleCacheRoot: cacheRoot),
              !isInsideProtectedHomeArea(forms),
              !Self.isCoreSimulatorStructure(forms.lexical),
              !Self.isCoreSimulatorStructure(forms.resolved),
              !containsStructuralAnchor(forms)
        else { return false }
        return true
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

    private static func isAndroidStudioPath(_ path: String) -> Bool {
        let components = path.split(separator: "/", omittingEmptySubsequences: true)
        for index in components.indices {
            guard index + 3 < components.count,
                  components[index] == "library",
                  components[index + 1] == "caches" || components[index + 1] == "application support",
                  components[index + 2] == "google"
            else { continue }
            let name = components[index + 3]
            if name == "androidstudio" || name == "androidstudiopreview" { return true }
            guard name.hasPrefix("androidstudio") || name.hasPrefix("androidstudiopreview") else { continue }
            let prefix = name.hasPrefix("androidstudiopreview") ? "androidstudiopreview" : "androidstudio"
            let version = name.dropFirst(prefix.count)
            if !version.isEmpty && version.allSatisfy({ $0.isNumber || $0 == "." }) { return true }
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

private extension ProtectedPaths {
    static func protectedAnchors(
        homePath: String,
        androidPrefixes: [String],
        gradlePrefixes: [String]
    ) -> [ProtectedPathForms] {
        var anchors = builtInProtectedRoots
            .filter { $0 != "/" }
            .map { ProtectedPathForms(path: $0) }
        anchors.append(ProtectedPathForms(path: homePath))
        anchors.append(contentsOf: (protectedHomeSubdirectories + anchoredHomeSubdirectories).map {
            ProtectedPathForms(path: (homePath as NSString).appendingPathComponent($0))
        })
        anchors.append(contentsOf: (androidPrefixes + gradlePrefixes).map { ProtectedPathForms(path: $0) })
        return anchors
    }

    /// Checks protected roots while allowing a Gradle cache child only.
    func isSystemProtected(_ forms: ProtectedPathForms, allowingGradleCacheRoot: URL? = nil) -> Bool {
        for spelling in forms.variants {
            if hasUnresolvedAndroidRedirects,
               spelling == homePath || spelling.hasPrefix(homePath + "/") {
                return true
            }
            if systemProtectedPaths.contains(spelling)
                || androidProtectedPrefixes.contains(where: { spelling == $0 || spelling.hasPrefix($0 + "/") })
                || isGradleSystemProtected(spelling, allowingCacheRoot: allowingGradleCacheRoot)
                || Self.isAndroidStudioPath(spelling)
                || Self.rootRestrictedPrefixes.contains(where: { spelling.hasPrefix($0) })
                || Self.isVolumeMountPoint(spelling)
                || isForeignUserPath(spelling) {
                return true
            }
        }
        return false
    }

    private func isGradleSystemProtected(_ spelling: String, allowingCacheRoot: URL?) -> Bool {
        let matchingHomes = gradleUserHomePrefixes.filter {
            spelling == $0 || spelling.hasPrefix($0 + "/")
        }
        guard !matchingHomes.isEmpty else { return false }
        guard let allowingCacheRoot else { return true }
        let cacheRoot = ProtectedPaths.normalize(allowingCacheRoot).lowercased()
        return !spelling.hasPrefix(cacheRoot + "/")
            || !matchingHomes.allSatisfy({ cacheRoot.hasPrefix($0 + "/") })
    }

    private func isInsideProtectedHomeArea(_ forms: ProtectedPathForms) -> Bool {
        let protectedRoots = (Self.protectedHomeSubdirectories + Self.anchoredHomeSubdirectories)
            .map { (homePath as NSString).appendingPathComponent($0).lowercased() }
        return forms.variants.contains { spelling in
            protectedRoots.contains { spelling == $0 || spelling.hasPrefix($0 + "/") }
        }
    }

    static func androidProtectedPrefixes(home: URL, homePath: String) -> [String] {
        let environment = ProcessInfo.processInfo.environment
        var paths = [
            (homePath as NSString).appendingPathComponent(".android"),
            (homePath as NSString).appendingPathComponent("Library/Android/sdk"),
            (homePath as NSString).appendingPathComponent("Library/Caches/Google/AndroidStudio"),
            (homePath as NSString).appendingPathComponent("Library/Application Support/Google/AndroidStudio")
        ]
        paths.append(contentsOf: RootResolver.androidStudioConfiguredSystemPaths(home: home).map {
            $0.path(percentEncoded: false)
        })
        for key in ["ANDROID_HOME", "ANDROID_SDK_ROOT", "ANDROID_AVD_HOME", "ANDROID_EMULATOR_HOME", "ANDROID_USER_HOME"] {
            if let root = RootResolver.absoluteAndroidPath(environment[key]) {
                paths.append(root.path(percentEncoded: false))
            }
        }
        for key in ["ANDROID_EMULATOR_HOME", "ANDROID_USER_HOME"] {
            if let root = RootResolver.absoluteAndroidPath(environment[key]) {
                paths.append(root.appendingPathComponent("avd", isDirectory: true).path(percentEncoded: false))
            }
        }
        paths.append(contentsOf: RootResolver.androidAVDRedirectPaths(home: home, environment: environment).map {
            $0.path(percentEncoded: false)
        })
        return Array(Set(paths.map(PathNormalizer.lexical))).sorted()
    }

    static func gradleUserHomePrefixes(homePath: String) -> [String] {
        var paths = [(homePath as NSString).appendingPathComponent(".gradle")]
        if let gradle = RootResolver.absoluteAndroidPath(ProcessInfo.processInfo.environment["GRADLE_USER_HOME"]) {
            paths.append(gradle.path(percentEncoded: false))
        }
        return Array(Set(paths.map(PathNormalizer.lexical))).sorted()
    }
}
