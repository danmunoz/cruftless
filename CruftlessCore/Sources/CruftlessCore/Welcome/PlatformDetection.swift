import Foundation

/// Which development platforms have tools or caches on this Mac.
public struct DetectedPlatforms: Sendable, Hashable {
    public let hasApple: Bool
    public let hasAndroid: Bool

    public init(hasApple: Bool, hasAndroid: Bool) {
        self.hasApple = hasApple
        self.hasAndroid = hasAndroid
    }

    public func contains(_ platform: DevelopmentPlatform) -> Bool {
        switch platform {
        case .apple: hasApple
        case .android: hasAndroid
        }
    }

    /// The scope to preselect; a Mac with nothing found scans everything.
    public var selection: PlatformSelection {
        var platforms: Set<DevelopmentPlatform> = []
        if hasApple { platforms.insert(.apple) }
        if hasAndroid { platforms.insert(.android) }
        return platforms.isEmpty ? .all : PlatformSelection(platforms)
    }

    /// What the welcome says under a platform's checkbox.
    public func note(for platform: DevelopmentPlatform) -> String {
        let scope = switch platform {
        case .apple: "Xcode, simulators and Swift packages."
        case .android: "Android Studio, SDK, emulators and Gradle."
        }
        return contains(platform) ? "\(scope) Found on this Mac." : "\(scope) Not found on this Mac."
    }
}

/// Finds which platforms are present, without opening any protected area.
public enum PlatformDetection: Sendable {
    /// Classifies already resolved facts.
    public static func detect(xcodeInstalls: [URL], hasXcodeUserData: Bool, androidRoots: [URL]) -> DetectedPlatforms {
        DetectedPlatforms(
            hasApple: !xcodeInstalls.isEmpty || hasXcodeUserData,
            hasAndroid: !androidRoots.isEmpty
        )
    }

    /// Looks at this Mac: Spotlight's Xcode installs, Xcode's own folder, and the Android roots that exist.
    public static func detectCurrent() async -> DetectedPlatforms {
        let installs = await XcodeInstallDiscovery.discover()
        let xcodeFolder = RootResolver.homeURL.appendingPathComponent("Library/Developer/Xcode", isDirectory: true)
        let hasXcodeUserData = FileManager.default.fileExists(atPath: xcodeFolder.path(percentEncoded: false))
        let androidRoots = RootResolver.androidStudioSystemRoots()
            + RootResolver.gradleCacheRoots()
            + RootResolver.androidSDKRoots()
            + RootResolver.androidAVDRoots()
        return detect(xcodeInstalls: installs, hasXcodeUserData: hasXcodeUserData, androidRoots: androidRoots)
    }
}
