import Foundation

public enum LocationCatalog: Sendable {
    public static let deviceSupport = TrackedLocation(
        id: "deviceSupport",
        title: "Device Support",
        icon: .symbol("cable.connector.horizontal"),
        tier: .regen,
        hasDrillDown: true,
        stalenessSource: .topLevelMtime,
        consequence: "Xcode re-creates it the next time that device is connected.",
        resolveRoots: RootResolver.deviceSupportRoots
    )

    public static let simulatorDevices = TrackedLocation(
        id: "simulatorDevices",
        title: "Simulator devices",
        icon: .symbol("iphone"),
        tier: .judgment,
        hasDrillDown: true,
        stalenessSource: .simulatorPlist,
        mutationPolicy: .simctl,
        resolveRoots: RootResolver.simulatorDevicesRoot
    )

    public static let simulatorRuntimes = TrackedLocation(
        id: "simulatorRuntimes",
        title: "Simulator runtimes",
        icon: .symbol("square.stack.3d.up"),
        tier: .judgment,
        hasDrillDown: true,
        stalenessSource: .topLevelMtime,
        sizeSource: .simulatorRuntimes,
        mutationPolicy: .simctl,
        resolveRoots: { [] }
    )

    public static let derivedData = TrackedLocation(
        id: "derivedData",
        title: "Derived Data",
        icon: .symbol("hammer"),
        tier: .regen,
        hasDrillDown: true,
        stalenessSource: .newestChildMtime,
        consequence: "Xcode rebuilds indexes and intermediates on the next build. The next build is slower.",
        resolveRoots: RootResolver.derivedDataRoots,
        resolveDefaultRoots: { [RootResolver.defaultDerivedDataRoot()] }
    )

    public static let previewsCache = TrackedLocation(
        id: "previewsCache",
        title: "Previews cache",
        icon: .symbol("eye"),
        tier: .regen,
        hasDrillDown: false,
        stalenessSource: .topLevelMtime,
        consequence: "Xcode Previews regenerates this the next time a preview runs.",
        resolveRoots: RootResolver.previewsCacheRoot
    )

    public static let toolchains = TrackedLocation(
        id: "toolchains",
        title: "Toolchains",
        icon: .symbol("wrench.adjustable"),
        tier: .judgment,
        hasDrillDown: true,
        stalenessSource: .topLevelMtime,
        consequence: "The toolchain must be re-downloaded and re-installed to use it again.",
        resolveRoots: RootResolver.toolchainsRoot
    )

    public static let swiftPMCache = TrackedLocation(
        id: "swiftPMCache",
        title: "SwiftPM cache",
        icon: .symbol("shippingbox"),
        tier: .judgment,
        hasDrillDown: false,
        stalenessSource: .topLevelMtime,
        consequence: "Packages are re-downloaded the next time they resolve. Needs a network connection.",
        resolveRoots: RootResolver.swiftPMCacheRoot
    )

    public static let ibSupport = TrackedLocation(
        id: "ibSupport",
        title: "Interface Builder support",
        icon: .symbol("rectangle.3.group"),
        tier: .regen,
        hasDrillDown: false,
        stalenessSource: .topLevelMtime,
        consequence: "Interface Builder rebuilds this on demand.",
        resolveRoots: RootResolver.ibSupportRoot
    )

    public static let archives = TrackedLocation(
        id: "archives",
        title: "Archives",
        icon: .symbol("archivebox"),
        tier: .irreversible,
        hasDrillDown: true,
        stalenessSource: .archiveCreationDate,
        consequence: "Deletes the dSYMs and the archived app. Crash reports from these builds can never be symbolicated, " +
            "and the build can't be re-exported.",
        resolveRoots: RootResolver.archivesRoot,
        resolveDefaultRoots: { [RootResolver.defaultArchivesRoot()] }
    )

    public static let codingAssistant = TrackedLocation(
        id: "codingAssistant",
        title: "Code completion models",
        icon: .symbol("sparkles"),
        tier: .judgment,
        hasDrillDown: false,
        stalenessSource: .topLevelMtime,
        consequence: "Coding assistant sessions, agent history and MCP server settings are lost.",
        resolveRoots: RootResolver.codingAssistantRoot
    )

    public static let productsLogsDocCache = TrackedLocation(
        id: "productsLogsDocCache",
        title: "Build products & logs",
        icon: .symbol("doc.text"),
        tier: .regen,
        hasDrillDown: false,
        stalenessSource: .topLevelMtime,
        consequence: "Build products and documentation caches are re-created on demand. Device logs are not.",
        resolveRoots: RootResolver.productsLogsDocCacheRoots
    )

    public static let xcodeInstalls = TrackedLocation(
        id: "xcodeInstalls",
        title: "Xcode installs",
        icon: .image("xcode"),
        tier: .reveal,
        hasDrillDown: true,
        stalenessSource: .topLevelMtime,
        resolveRoots: RootResolver.xcodeInstallsRoots
    )

    public static let simulatorDyldCache = TrackedLocation(
        id: "simulatorDyldCache",
        title: "Simulator dyld cache",
        icon: .symbol("internaldrive"),
        tier: .info,
        hasDrillDown: false,
        stalenessSource: .topLevelMtime,
        resolveRoots: RootResolver.simulatorDyldCacheRoot
    )

    /// All 13 locations in canonical catalog order.
    public static let all: [TrackedLocation] = [
        deviceSupport,
        simulatorDevices,
        simulatorRuntimes,
        derivedData,
        previewsCache,
        toolchains,
        swiftPMCache,
        ibSupport,
        archives,
        codingAssistant,
        productsLogsDocCache,
        xcodeInstalls,
        simulatorDyldCache
    ]
}
