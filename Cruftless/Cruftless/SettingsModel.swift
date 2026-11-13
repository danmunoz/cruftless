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
    public var isDeletionExecuting = false {
        didSet {
            guard oldValue, !isDeletionExecuting else { return }
            platformSelectionError = SettingsControlPolicy.clearingBusyMessage(platformSelectionError)
            protectedPathError = SettingsControlPolicy.clearingBusyMessage(protectedPathError)
        }
    }

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

    /// The login item's own explanation, shown whenever the status needs one and no write failure is on screen.
    public var launchAtLoginNotice: String? {
        launchAtLoginError == nil ? LaunchAtLoginPolicy.statusMessage(for: launchAtLoginStatus) : nil
    }

    public var launchAtLoginNeedsApproval: Bool {
        LaunchAtLoginPolicy.needsApproval(launchAtLoginStatus)
    }

    public var canEditProtectedPaths: Bool {
        SettingsControlPolicy.allowsProtectedPathEdits(isDeletionExecuting: isDeletionExecuting)
    }

    public var showsPlatformOrder: Bool {
        SettingsControlPolicy.showsPlatformOrder(for: platformSelection)
    }

    public func isPlatformToggleDisabled(_ platform: DevelopmentPlatform) -> Bool {
        SettingsControlPolicy.isPlatformToggleDisabled(
            platform,
            selection: platformSelection,
            isDeletionExecuting: isDeletionExecuting
        )
    }

    private let defaults: UserDefaults
    public let protectedPathsStore: ProtectedPathsStore
    public let policyGenerationAuthority: PolicyGenerationAuthority
    private let reminderScheduler: ScanReminderScheduler
    private let loginItemService: any LoginItemService
    private var reminderTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        protectedPathsStore: ProtectedPathsStore = .shared,
        policyGenerationAuthority: PolicyGenerationAuthority = PolicyGenerationAuthority(),
        reminderCenter: any ScanReminderCenter = UserNotificationReminderCenter(),
        loginItemService: any LoginItemService = SystemLoginItemService()
    ) {
        self.defaults = defaults
        self.loginItemService = loginItemService
        reminderScheduler = ScanReminderScheduler(center: reminderCenter)
        self.protectedPathsStore = protectedPathsStore
        self.policyGenerationAuthority = policyGenerationAuthority
        launchAtLoginStatus = loginItemService.status
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

    // MARK: - Scanning

    public func setPlatformSectionOrder(_ order: PlatformSectionOrder) {
        guard order != storedPlatformSectionOrder else { return }
        storedPlatformSectionOrder = order
        defaults.set(order.rawValue, forKey: Keys.platformSectionOrder)
    }

    public func setPlatformEnabled(_ platform: DevelopmentPlatform, _ enabled: Bool) {
        guard !isDeletionExecuting else {
            platformSelectionError = SettingsControlPolicy.platformSelectionBusyMessage
            return
        }
        guard let updated = SettingsControlPolicy.updatedSelection(
            from: platformSelection,
            platform: platform,
            enabled: enabled
        ) else { return }
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

    /// Turns the reminder off when the system has since refused notifications.
    public func refreshScanReminderAuthorization() {
        guard scanReminderEnabled else { return }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await reminderScheduler.checkPermission()
            guard scanReminderEnabled, let message = outcome?.failureMessage else { return }
            reminderTask?.cancel()
            reminderTask = nil
            reminderScheduler.disarm()
            failScanReminder(message)
        }
    }

    private func failScanReminder(_ message: String) {
        scanReminderEnabled = false
        defaults.set(false, forKey: Keys.scanReminderEnabled)
        scanReminderError = message
    }

    // MARK: - Protected paths

    /// Reports a folder picker error; a cancelled pick reports nothing.
    public func reportFolderPickerFailure(_ error: any Error) {
        protectedPathError = ProtectedPathPolicy.pickerFailureMessage(for: error)
    }

    /// Vets the folder before storing it.
    public func addProtectedPath(_ url: URL) {
        guard !isDeletionExecuting else {
            protectedPathError = SettingsControlPolicy.protectedPathsBusyMessage
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
            protectedPathError = SettingsControlPolicy.protectedPathsBusyMessage
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

public extension SettingsModel {
    // MARK: - Launch at login

    func setLaunchAtLogin(_ enabled: Bool) {
        launchAtLoginRevision &+= 1

        var failure: String?
        do {
            if enabled {
                try loginItemService.register()
            } else {
                try loginItemService.unregister()
            }
        } catch {
            failure = error.localizedDescription
        }

        let status = loginItemService.status
        launchAtLoginStatus = status
        launchAtLoginError = LaunchAtLoginPolicy.failureMessage(requested: enabled, status: status, failure: failure)
    }

    func openLoginItemsSettings() {
        loginItemService.openSystemSettings()
    }

    /// Re-reads every system-owned state the General pane mirrors.
    func refreshSystemState() {
        refreshLaunchAtLoginStatus()
        refreshScanReminderAuthorization()
    }

    /// Re-reads the login item's state from the system, picking up an approval or removal made in System Settings.
    func refreshLaunchAtLoginStatus() {
        let status = loginItemService.status
        guard status != launchAtLoginStatus else { return }
        launchAtLoginStatus = status
        launchAtLoginError = nil
    }
}

#if DEBUG
    extension SettingsModel {
        static func preview(
            protectedPaths: [URL] = [],
            launchAtLoginStatus: SMAppService.Status = .notRegistered,
            launchAtLoginError: String? = nil,
            scanReminderError: String? = nil,
            protectedPathError: String? = nil,
            platformSelectionError: String? = nil,
            isDeletionExecuting: Bool = false,
            platforms: Set<DevelopmentPlatform> = Set(DevelopmentPlatform.allCases),
            platformSectionOrder: PlatformSectionOrder = .appleFirst
        ) -> SettingsModel {
            let suiteName = "Cruftless.SettingsPreview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let store = ProtectedPathsStore(userDefaults: defaults)
            for path in protectedPaths {
                store.addPath(path)
            }
            let model = SettingsModel(
                defaults: defaults,
                protectedPathsStore: store,
                loginItemService: FixedLoginItemService(status: launchAtLoginStatus)
            )
            model.setPlatformSectionOrder(platformSectionOrder)
            if platforms != Set(DevelopmentPlatform.allCases) {
                for platform in DevelopmentPlatform.allCases {
                    model.setPlatformEnabled(platform, platforms.contains(platform))
                }
            }
            model.isDeletionExecuting = isDeletionExecuting
            model.launchAtLoginError = launchAtLoginError
            model.scanReminderError = scanReminderError
            model.protectedPathError = protectedPathError
            model.platformSelectionError = platformSelectionError
            return model
        }
    }
#endif
