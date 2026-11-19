import CruftlessCore
import Foundation
import Observation

/// Drives the first-run welcome window.
@MainActor
@Observable
public final class WelcomeModel {
    /// True until the welcome is finished or its window is closed.
    public private(set) var isPending: Bool
    public private(set) var step: WelcomeStep = .location
    /// What was found on this Mac, nil until the check returns.
    public private(set) var detected: DetectedPlatforms?
    public private(set) var hasAccessNeeds = false
    /// True until the access check for the current platform selection has answered.
    public private(set) var isCheckingAccess = true
    public let settings: SettingsModel

    /// Runs once, when the welcome is finished or its window is closed.
    public var onFinish: (() -> Void)?

    private let defaults: UserDefaults
    private let detect: @Sendable () async -> DetectedPlatforms
    private let findAccessNeeds: @Sendable ([TrackedLocation]) async -> Bool
    /// False when the welcome is forced for inspection, so it changes no saved setting.
    private let persistsChoices: Bool
    private var hasPrepared = false
    /// True when the access step is forced for inspection, whatever the check finds.
    private var forcesAccessStep = false
    private var accessCheckGeneration = 0

    public var steps: [WelcomeStep] {
        WelcomePolicy.steps(hasAccessNeeds: hasAccessNeeds)
    }

    public var isFirstStep: Bool {
        WelcomePolicy.step(before: step, in: steps) == nil
    }

    public var isLastStep: Bool {
        WelcomePolicy.step(after: step, in: steps) == nil
    }

    /// True when the primary action of the current step starts the first scan.
    public var startsScanNext: Bool {
        WelcomePolicy.startsScan(after: step, in: steps)
    }

    /// False on the platform step while the access check is out, so its label never changes under a click.
    public var canAdvance: Bool {
        !(step == .setup && isCheckingAccess)
    }

    public init(
        settings: SettingsModel,
        hasSavedInventory: Bool,
        defaults: UserDefaults = .standard,
        detect: @escaping @Sendable () async -> DetectedPlatforms = { await PlatformDetection.detectCurrent() },
        findAccessNeeds: @escaping @Sendable ([TrackedLocation]) async -> Bool = { catalog in
            await !AccessPreflight.needs(catalog: catalog).isEmpty
        }
    ) {
        self.settings = settings
        self.defaults = defaults
        self.detect = detect
        self.findAccessNeeds = findAccessNeeds

        var isForced = false
        #if DEBUG
            isForced = defaults.bool(forKey: DebugKeys.forceWelcome)
        #endif
        persistsChoices = !isForced
        isPending = isForced || WelcomePolicy.shouldShow(
            isCompleted: defaults.bool(forKey: WelcomePolicy.completedKey),
            hasSavedInventory: hasSavedInventory
        )
        #if DEBUG
            if isForced, let raw = defaults.string(forKey: DebugKeys.step), let forcedStep = WelcomeStep(rawValue: raw) {
                step = forcedStep
                forcesAccessStep = forcedStep == .access
                hasAccessNeeds = forcesAccessStep
            }
        #endif
    }

    /// Detects platforms, preselects them, and finds out whether the access step is needed.
    public func prepare() async {
        guard !hasPrepared else { return }
        hasPrepared = true

        let found = await detect()
        detected = found
        if persistsChoices {
            preselect(found.selection)
        }

        await refreshAccessNeeds()
        if step == .scan {
            finish()
        }
    }

    /// Re-runs the access check for the selected platforms; a newer call supersedes an older one.
    public func refreshAccessNeeds() async {
        accessCheckGeneration += 1
        let generation = accessCheckGeneration
        isCheckingAccess = true
        let needsAccess = await findAccessNeeds(settings.activeCatalog.locations)
        guard generation == accessCheckGeneration else { return }
        hasAccessNeeds = forcesAccessStep || needsAccess
        isCheckingAccess = false
        step = WelcomePolicy.resolved(step, in: steps)
    }

    /// Moves forward; entering the scan step is what starts the first scan.
    public func advance() {
        guard canAdvance, let next = WelcomePolicy.step(after: step, in: steps) else { return }
        if next == .scan {
            finish()
        }
        step = next
    }

    public func back() {
        guard let previous = WelcomePolicy.step(before: step, in: steps) else { return }
        step = previous
    }

    /// Records that the welcome was seen and hands over to the app, which starts the first scan.
    public func finish() {
        guard isPending else { return }
        isPending = false
        if persistsChoices {
            defaults.set(true, forKey: WelcomePolicy.completedKey)
        }
        onFinish?()
    }

    /// Enables before disabling, so the selection never passes through empty.
    private func preselect(_ selection: PlatformSelection) {
        for platform in DevelopmentPlatform.allCases where selection.platforms.contains(platform) {
            settings.setPlatformEnabled(platform, true)
        }
        for platform in DevelopmentPlatform.allCases where !selection.platforms.contains(platform) {
            settings.setPlatformEnabled(platform, false)
        }
    }
}

#if DEBUG
    extension WelcomeModel {
        /// Launch arguments that show the welcome on a Mac that has already finished it.
        enum DebugKeys {
            static let forceWelcome = "cruftless.debug.forceWelcome"
            static let step = "cruftless.debug.welcomeStep"
        }

        static func preview(
            step: WelcomeStep = .location,
            hasAccessNeeds: Bool = false,
            detected: DetectedPlatforms? = DetectedPlatforms(hasApple: true, hasAndroid: false),
            settings: SettingsModel = .preview(platforms: [.apple])
        ) -> WelcomeModel {
            let suiteName = "Cruftless.WelcomePreview.\(UUID().uuidString)"
            let model = WelcomeModel(
                settings: settings,
                hasSavedInventory: false,
                defaults: UserDefaults(suiteName: suiteName)!,
                detect: { detected ?? DetectedPlatforms(hasApple: false, hasAndroid: false) },
                findAccessNeeds: { _ in hasAccessNeeds }
            )
            model.hasPrepared = true
            model.detected = detected
            model.hasAccessNeeds = hasAccessNeeds
            model.forcesAccessStep = hasAccessNeeds
            model.isCheckingAccess = false
            model.step = WelcomePolicy.resolved(step, in: model.steps)
            return model
        }
    }
#endif
