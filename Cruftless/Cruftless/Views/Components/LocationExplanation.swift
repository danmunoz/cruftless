import CruftlessCore
import Foundation

struct LocationExplanation {
    let description: LocalizedStringResource
    let risk: LocalizedStringResource

    static func explanation(for location: TrackedLocation) -> LocationExplanation {
        explanations[location.id] ?? LocationExplanation(
            description: "Development files stored in this location.",
            risk: "\(location.consequence)"
        )
    }

    private static let explanations: [String: LocationExplanation] = [
        LocationCatalog.deviceSupport.id: LocationExplanation(
            description: "Files Xcode uses to debug apps on connected Apple devices, grouped by operating system version.",
            risk: "Xcode recreates them when needed. The next connection may take longer while it prepares the device."
        ),
        LocationCatalog.simulatorDevices.id: LocationExplanation(
            description: "Virtual Apple devices, including their installed apps, settings, and app data.",
            risk: """
            Erasing resets the device and permanently removes its apps and data. \
            Deleting also removes the device itself. Clearing only caches preserves installed apps and their data.
            """
        ),
        LocationCatalog.simulatorRuntimes.id: LocationExplanation(
            description: "Operating system packages that let simulators run a particular version of iOS, watchOS, tvOS, or visionOS.",
            risk: "Simulators that need this version cannot run until you reinstall it. Reinstallation requires a large download."
        ),
        LocationCatalog.derivedData.id: LocationExplanation(
            description: "Build files and code indexes Xcode generates while you work on projects.",
            risk: "Xcode rebuilds these files. The next build and code indexing may take longer."
        ),
        LocationCatalog.previewsCache.id: LocationExplanation(
            description: "Generated files and temporary simulator storage used by Xcode’s interface previews.",
            risk: "Xcode recreates these files when previews run again. The next preview may take longer to load."
        ),
        LocationCatalog.toolchains.id: LocationExplanation(
            description: "Additional compilers and development tools, such as separately installed Swift versions.",
            risk: """
            Projects that use a removed toolchain may stop building until you reinstall it or select another \
            compatible toolchain.
            """
        ),
        LocationCatalog.swiftPMCache.id: LocationExplanation(
            description: "Cached downloads used by Swift Package Manager to load project dependencies.",
            risk: """
            Packages may need downloading again. Builds can fail without internet access or if a dependency is no \
            longer available.
            """
        ),
        LocationCatalog.ibSupport.id: LocationExplanation(
            description: "Generated support files used by Xcode to display and edit storyboards and interface files.",
            risk: "Xcode recreates these files when needed. Interface Builder may take longer to load initially."
        ),
        LocationCatalog.archives.id: LocationExplanation(
            description: "Saved app builds prepared for distribution, including files needed to interpret crash reports.",
            risk: """
            You lose the saved build and its debugging symbols. Without another copy, \
            you cannot export that build again or fully interpret its crash reports.
            """
        ),
        LocationCatalog.codingAssistant.id: LocationExplanation(
            description: "Data stored by Xcode’s coding assistants, including conversations, agent history, and integration settings.",
            risk: "Deleting can permanently remove history and settings. You may need to configure integrations again."
        ),
        LocationCatalog.productsLogsDocCache.id: LocationExplanation(
            description: "Generated app builds, cached documentation, and logs collected from devices.",
            risk: """
            Builds and documentation caches can be recreated. Deleted device logs are lost \
            and may be needed to investigate problems.
            """
        ),
        LocationCatalog.xcodeInstalls.id: LocationExplanation(
            description: "Copies of the Xcode application, each with its own development tools and supported platforms.",
            risk: """
            Removing a version can disrupt projects or scripts that depend on it. \
            Cruftless shows these in Finder; it does not delete them.
            """
        ),
        LocationCatalog.simulatorDyldCache.id: LocationExplanation(
            description: "Cached system libraries used to help simulator apps start efficiently.",
            risk: """
            Manual cleanup requires administrator access and may slow simulator startup while caches are rebuilt. \
            Cruftless cannot delete these directly.
            """
        ),
        LocationCatalog.androidStudioSystem.id: LocationExplanation(
            description: "Android Studio’s caches, code indexes, and Local History, which stores earlier versions of your files.",
            risk: "Deleting the whole folder can permanently remove Local History. Cruftless keeps this section read-only."
        ),
        LocationCatalog.gradleCaches.id: LocationExplanation(
            description: """
            Downloaded dependencies and cached build work shared by Gradle projects, \
            including projects outside Android Studio.
            """,
            risk: """
            Clearing files while Gradle is using them can interrupt builds. Later builds may need rebuilding \
            or downloading dependencies, and offline builds may fail. \
            Cruftless requires separate risk acceptance before cleanup.
            """
        ),
        LocationCatalog.androidSDK.id: LocationExplanation(
            description: "Android development packages, including build tools, platform versions, and emulator system images.",
            risk: """
            Removing required packages can stop projects building or emulators starting. \
            Cruftless keeps this section read-only; manage packages in Android Studio’s SDK Manager.
            """
        ),
        LocationCatalog.androidAVDs.id: LocationExplanation(
            description: "Virtual Android devices, including installed apps, settings, saved states, and device storage.",
            risk: """
            Wiping or deleting a device permanently removes its stored apps and data. \
            Cruftless removes one stopped, inactive device through Google’s Android CLI after review. \
            Missing tools require installation permission. Do not start the device during removal.
            """
        )
    ]
}
