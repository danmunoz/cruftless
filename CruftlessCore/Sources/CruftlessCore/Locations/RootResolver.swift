import Foundation

/// Resolves filesystem root URLs for all tracked locations.
public enum RootResolver: Sendable {
    private static var homeURL: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    /// Xcode's preference domain.
    private static let xcodePreferenceSuite = "com.apple.dt.Xcode"

    public static let derivedDataPreferenceKey = "IDECustomDerivedDataLocation"
    public static let archivesPreferenceKey = "IDECustomDistributionArchivesLocation"

    // MARK: - Custom locations

    public static func derivedDataRoots() -> [URL] {
        [resolveCustom(key: derivedDataPreferenceKey, defaultRoot: defaultDerivedDataRoot(home: homeURL)).root]
    }

    /// Archives root, respecting `IDECustomDistributionArchivesLocation` under the same policy.
    public static func archivesRoot() -> [URL] {
        [resolveCustom(key: archivesPreferenceKey, defaultRoot: defaultArchivesRoot(home: homeURL)).root]
    }

    public static func preferenceIssues() -> [RootPreferenceIssue] {
        [
            resolveCustom(key: derivedDataPreferenceKey, defaultRoot: defaultDerivedDataRoot(home: homeURL)).issue,
            resolveCustom(key: archivesPreferenceKey, defaultRoot: defaultArchivesRoot(home: homeURL)).issue
        ].compactMap(\.self)
    }

    public static func fixedTrackedRoots(home: URL) -> [URL] {
        deviceSupportRoots(home: home)
            + simulatorDevicesRoot(home: home)
            + previewsCacheRoot(home: home)
            + toolchainsRoot(home: home)
            + swiftPMCacheRoot(home: home)
            + ibSupportRoot(home: home)
            + codingAssistantRoot(home: home)
            + productsLogsDocCacheRoots(home: home)
            + simulatorDyldCacheRoot()
            + [
                home.appendingPathComponent("Library/Developer", isDirectory: true),
                defaultDerivedDataRoot(home: home),
                defaultArchivesRoot(home: home)
            ]
    }

    public static func defaultDerivedDataRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Developer/Xcode/DerivedData", isDirectory: true)
    }

    public static func defaultArchivesRoot(home: URL) -> URL {
        home.appendingPathComponent("Library/Developer/Xcode/Archives", isDirectory: true)
    }

    public static func defaultDerivedDataRoot() -> URL {
        defaultDerivedDataRoot(home: homeURL)
    }

    public static func defaultArchivesRoot() -> URL {
        defaultArchivesRoot(home: homeURL)
    }

    private static func resolveCustom(key: String, defaultRoot: URL) -> (root: URL, issue: RootPreferenceIssue?) {
        let raw = UserDefaults(suiteName: xcodePreferenceSuite)?.string(forKey: key)
        guard let raw, !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return (defaultRoot, nil)
        }
        let home = homeURL
        return customRoot(
            preferenceKey: key,
            preference: raw,
            fallback: defaultRoot,
            policy: .standard(home: home, protectedPaths: ProtectedPathsStore.shared.protectedPaths())
        )
    }

    // MARK: - Fixed locations

    /// iOS, watchOS, tvOS, visionOS Device Support directories.
    public static func deviceSupportRoots() -> [URL] {
        deviceSupportRoots(home: homeURL)
    }

    public static func simulatorDevicesRoot() -> [URL] {
        simulatorDevicesRoot(home: homeURL)
    }

    public static func previewsCacheRoot() -> [URL] {
        previewsCacheRoot(home: homeURL)
    }

    public static func toolchainsRoot() -> [URL] {
        toolchainsRoot(home: homeURL)
    }

    public static func swiftPMCacheRoot() -> [URL] {
        swiftPMCacheRoot(home: homeURL)
    }

    public static func ibSupportRoot() -> [URL] {
        ibSupportRoot(home: homeURL)
    }

    public static func codingAssistantRoot() -> [URL] {
        codingAssistantRoot(home: homeURL)
    }

    public static func productsLogsDocCacheRoots() -> [URL] {
        productsLogsDocCacheRoots(home: homeURL)
    }

    public static func simulatorDyldCacheRoot() -> [URL] {
        [URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld", isDirectory: true)]
    }

    static func deviceSupportRoots(home: URL) -> [URL] {
        let xcodeDir = home.appendingPathComponent("Library/Developer/Xcode", isDirectory: true)
        let candidates = [
            "iOS DeviceSupport",
            "watchOS DeviceSupport",
            "tvOS DeviceSupport",
            "visionOS DeviceSupport"
        ]
        return candidates.map { xcodeDir.appendingPathComponent($0, isDirectory: true) }
    }

    static func simulatorDevicesRoot(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Developer/CoreSimulator/Devices", isDirectory: true)]
    }

    static func previewsCacheRoot(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Developer/Xcode/UserData/Previews", isDirectory: true)]
    }

    static func toolchainsRoot(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Developer/Toolchains", isDirectory: true)]
    }

    static func swiftPMCacheRoot(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Caches/org.swift.swiftpm", isDirectory: true)]
    }

    static func ibSupportRoot(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Developer/Xcode/UserData/IB Support", isDirectory: true)]
    }

    static func codingAssistantRoot(home: URL) -> [URL] {
        [home.appendingPathComponent("Library/Developer/Xcode/CodingAssistant", isDirectory: true)]
    }

    static func productsLogsDocCacheRoots(home: URL) -> [URL] {
        let xcodeDir = home.appendingPathComponent("Library/Developer/Xcode", isDirectory: true)
        return [
            xcodeDir.appendingPathComponent("Products", isDirectory: true),
            xcodeDir.appendingPathComponent("iOS Device Logs", isDirectory: true),
            xcodeDir.appendingPathComponent("DocumentationCache", isDirectory: true)
        ]
    }

    // MARK: - Xcode installs

    /// Installed Xcode applications, as discovered so far.
    public static func xcodeInstallsRoots() -> [URL] {
        XcodeInstallDiscovery.knownInstalls()
    }

    /// Resolves anything that needs a subprocess, once.
    public static func prepare() async {
        await XcodeInstallDiscovery.discover()
    }
}
