import CruftlessCore
import Foundation
import Observation
import ServiceManagement

public enum PlatformSectionOrder: String, CaseIterable, Hashable, Identifiable, Sendable {
    case appleFirst
    case androidFirst

    public var id: Self {
        self
    }

    public var orderedPlatforms: [DevelopmentPlatform] {
        switch self {
        case .appleFirst: [.apple, .android]
        case .androidFirst: [.android, .apple]
        }
    }
}

@MainActor
@Observable
public final class SettingsModel {
    /// The login item's real state, not a mirror of what the switch last drew.
    public private(set) var launchAtLoginStatus: SMAppService.Status
    public private(set) var scanReminderEnabled: Bool
    public private(set) var protectedPaths: [URL]
    public private(set) var platformSelection: PlatformSelection
    private var storedPlatformSectionOrder: PlatformSectionOrder
    public private(set) var platformGeneration: UInt64 = 0
    public private(set) var platformSelectionError: String?
    public var isDeletionExecuting = false
    public private(set) var launchAtLoginError: String?
    public private(set) var scanReminderError: String?
    public private(set) var protectedPathError: String?

    public var onPlatformSelectionChanged: ((ActiveCatalog) -> Void)?

    /// Bumped on every write attempt, and read by `isLaunchAtLoginEnabled` so the getter re-evaluates each time.
    private var launchAtLoginRevision = 0

    public var isLaunchAtLoginEnabled: Bool {
        get {
            _ = launchAtLoginRevision
            return launchAtLoginStatus == .enabled
        }
        set { setLaunchAtLogin(newValue) }
    }

    public var isScanReminderEnabled: Bool {
        get { scanReminderEnabled }
        set { setScanReminderEnabled(newValue) }
    }

    public var platformSectionOrder: PlatformSectionOrder {
        get { storedPlatformSectionOrder }
        set { setPlatformSectionOrder(newValue) }
    }

    public var protectedPathPolicy: ProtectedPaths {
        protectedPathsStore.protectedPaths()
    }

    /// Rows the General pane renders only when something failed.
    public var visibleErrorRowCount: Int {
        [launchAtLoginError, scanReminderError, protectedPathError, platformSelectionError].count { $0 != nil }
    }

    private let defaults: UserDefaults
    public let protectedPathsStore: ProtectedPathsStore
    public let policyGenerationAuthority: PolicyGenerationAuthority
    private let reminderScheduler: ScanReminderScheduler
    private var reminderTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        protectedPathsStore: ProtectedPathsStore = .shared,
        policyGenerationAuthority: PolicyGenerationAuthority = PolicyGenerationAuthority(),
        reminderCenter: any ScanReminderCenter = UserNotificationReminderCenter()
    ) {
        self.defaults = defaults
        reminderScheduler = ScanReminderScheduler(center: reminderCenter)
        self.protectedPathsStore = protectedPathsStore
        self.policyGenerationAuthority = policyGenerationAuthority
        launchAtLoginStatus = SMAppService.mainApp.status
        scanReminderEnabled = defaults.bool(forKey: Keys.scanReminderEnabled)
        storedPlatformSectionOrder = PlatformSectionOrder(
            rawValue: defaults.string(forKey: Keys.platformSectionOrder) ?? ""
        ) ?? .appleFirst
        let savedPlatforms = defaults.stringArray(forKey: Keys.selectedPlatforms)
        let migratedSelection = savedPlatforms == nil
            ? PlatformSelection.all
            : PlatformSelection.migrate(savedPlatforms)
        let initialGeneration: UInt64 = 0
        platformSelection = migratedSelection
        platformGeneration = initialGeneration
        defaults.set(migratedSelection.identifiers, forKey: Keys.selectedPlatforms)
        policyGenerationAuthority.update(
            to: initialGeneration,
            readOnlyLocationIDs: Set(LocationCatalog.all.filter { $0.mutationPolicy == .readOnly }.map(\.id))
        )
        protectedPaths = protectedPathsStore.customPaths()

        if scanReminderEnabled {
            startReminderScheduling()
        }
    }

    // MARK: - Launch at login

    public func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginRevision &+= 1

        var failure: String?
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            failure = error.localizedDescription
        }

        let status = SMAppService.mainApp.status
        launchAtLoginStatus = status
        launchAtLoginError = LaunchAtLoginPolicy.message(requested: enabled, status: status, failure: failure)
    }

    /// Re-reads the login item's state from the system, picking up an approval or removal made in System Settings.
    public func refreshLaunchAtLoginStatus() {
        let status = SMAppService.mainApp.status
        guard status != launchAtLoginStatus else { return }
        launchAtLoginStatus = status
        launchAtLoginError = nil
    }

    // MARK: - Scanning

    public func setPlatformSectionOrder(_ order: PlatformSectionOrder) {
        guard order != storedPlatformSectionOrder else { return }
        storedPlatformSectionOrder = order
        defaults.set(order.rawValue, forKey: Keys.platformSectionOrder)
    }

    public func setPlatformEnabled(_ platform: DevelopmentPlatform, _ enabled: Bool) {
        guard !isDeletionExecuting else {
            platformSelectionError = "Platform selection is unavailable while a deletion is running."
            return
        }
        var selected = platformSelection.platforms
        if enabled {
            selected.insert(platform)
        } else {
            guard selected.contains(platform), selected.count > 1 else { return }
            selected.remove(platform)
        }
        let updated = PlatformSelection(selected)
        guard updated != platformSelection else { return }
        platformSelectionError = nil
        platformSelection = updated
        defaults.set(updated.identifiers, forKey: Keys.selectedPlatforms)
        advancePolicyGeneration()
    }

    public var activeCatalog: ActiveCatalog {
        platformSelection.catalog(generation: platformGeneration)
    }

    public func setScanReminderEnabled(_ enabled: Bool) {
        scanReminderEnabled = enabled
        defaults.set(enabled, forKey: Keys.scanReminderEnabled)
        reminderTask?.cancel()
        reminderTask = nil
        scanReminderError = nil

        if enabled {
            startReminderScheduling()
        } else {
            defaults.removeObject(forKey: Keys.scanReminderSchedule)
            reminderScheduler.disarm()
        }
    }

    private func startReminderScheduling() {
        reminderTask?.cancel()
        let generation = platformGeneration
        reminderTask = Task { [weak self] in
            await self?.armReminder(generation: generation)
        }
    }

    private func armReminder(generation: UInt64) async {
        let outcome = await reminderScheduler.arm(
            body: ScanReminderScheduler.body(for: platformSelection.platforms),
            storedSchedule: storedReminderSchedule
        )
        guard scanReminderEnabled else {
            reminderScheduler.disarm()
            return
        }
        guard !Task.isCancelled else { return }

        if let message = outcome.failureMessage {
            failScanReminder(message)
            return
        }
        if case let .scheduled(schedule) = outcome {
            storeReminderSchedule(schedule)
        }
        if generation != platformGeneration { startReminderScheduling() }
    }

    private var storedReminderSchedule: ScanReminderSchedule? {
        defaults.data(forKey: Keys.scanReminderSchedule)
            .flatMap { try? JSONDecoder().decode(ScanReminderSchedule.self, from: $0) }
    }

    private func storeReminderSchedule(_ schedule: ScanReminderSchedule) {
        guard let data = try? JSONEncoder().encode(schedule) else { return }
        defaults.set(data, forKey: Keys.scanReminderSchedule)
    }

    private func failScanReminder(_ message: String) {
        scanReminderEnabled = false
        defaults.set(false, forKey: Keys.scanReminderEnabled)
        scanReminderError = message
    }

    // MARK: - Protected paths

    /// Vets the folder before storing it.
    public func addProtectedPath(_ url: URL) {
        guard !isDeletionExecuting else {
            protectedPathError = "Protected paths cannot change while a deletion is running."
            return
        }
        if let rejection = ProtectedPathPolicy.rejection(for: url, existing: protectedPaths) {
            protectedPathError = rejection.message
            return
        }
        protectedPathError = nil
        advancePolicyGeneration(notify: false)
        protectedPathsStore.addPath(url)
        protectedPaths = protectedPathsStore.customPaths()
        onPlatformSelectionChanged?(activeCatalog)
    }

    public func removeProtectedPath(_ url: URL) {
        guard !isDeletionExecuting else {
            protectedPathError = "Protected paths cannot change while a deletion is running."
            return
        }
        guard protectedPaths.contains(where: { ProtectedPaths.normalize($0) == ProtectedPaths.normalize(url) }) else {
            return
        }
        protectedPathError = nil
        advancePolicyGeneration(notify: false)
        protectedPathsStore.removePath(url)
        protectedPaths = protectedPathsStore.customPaths()
        onPlatformSelectionChanged?(activeCatalog)
    }

    private func advancePolicyGeneration(notify: Bool = true) {
        platformGeneration &+= 1
        let readOnlyIDs = LocationCatalog.all.filter { $0.mutationPolicy == .readOnly }.map(\.id)
        policyGenerationAuthority.update(to: platformGeneration, readOnlyLocationIDs: Set(readOnlyIDs))
        if scanReminderEnabled { startReminderScheduling() }
        if notify { onPlatformSelectionChanged?(activeCatalog) }
    }

    // MARK: - Helpers

    private enum Keys {
        static let scanReminderEnabled = "scanReminderEnabled"
        static let selectedPlatforms = "selectedPlatforms"
        static let platformSectionOrder = "platformSectionOrder"
        static let scanReminderSchedule = "scanReminderSchedule"
    }
}

#if DEBUG
    extension SettingsModel {
        static func preview(
            protectedPaths: [URL] = [],
            launchAtLoginError: String? = nil,
            scanReminderError: String? = nil,
            protectedPathError: String? = nil,
            platforms: Set<DevelopmentPlatform> = Set(DevelopmentPlatform.allCases),
            platformSectionOrder: PlatformSectionOrder = .appleFirst
        ) -> SettingsModel {
            let suiteName = "Cruftless.SettingsPreview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let store = ProtectedPathsStore(userDefaults: defaults)
            for path in protectedPaths {
                store.addPath(path)
            }
            let model = SettingsModel(defaults: defaults, protectedPathsStore: store)
            model.setPlatformSectionOrder(platformSectionOrder)
            if platforms != Set(DevelopmentPlatform.allCases) {
                for platform in DevelopmentPlatform.allCases {
                    model.setPlatformEnabled(platform, platforms.contains(platform))
                }
            }
            model.launchAtLoginError = launchAtLoginError
            model.scanReminderError = scanReminderError
            model.protectedPathError = protectedPathError
            return model
        }
    }
#endif
