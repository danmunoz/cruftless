import CruftlessCore
import Foundation
import Observation
import ServiceManagement
import UserNotifications

@MainActor
@Observable
public final class SettingsModel {
    /// The login item's real state, not a mirror of what the switch last drew.
    public private(set) var launchAtLoginStatus: SMAppService.Status
    public private(set) var scanReminderEnabled: Bool
    public private(set) var protectedPaths: [URL]
    public private(set) var launchAtLoginError: String?
    public private(set) var scanReminderError: String?
    public private(set) var protectedPathError: String?

    /// Called after the protected list changes.
    public var onProtectedPathsChanged: (() -> Void)?

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

    public var protectedPathPolicy: ProtectedPaths {
        protectedPathsStore.protectedPaths()
    }

    /// Rows the General pane renders only when something failed.
    public var visibleErrorRowCount: Int {
        [launchAtLoginError, scanReminderError, protectedPathError].count { $0 != nil }
    }

    private let defaults: UserDefaults
    private let protectedPathsStore: ProtectedPathsStore
    private var reminderTask: Task<Void, Never>?

    public init(
        defaults: UserDefaults = .standard,
        protectedPathsStore: ProtectedPathsStore = .shared
    ) {
        self.defaults = defaults
        self.protectedPathsStore = protectedPathsStore
        launchAtLoginStatus = SMAppService.mainApp.status
        scanReminderEnabled = defaults.bool(forKey: Keys.scanReminderEnabled)
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

    public func setScanReminderEnabled(_ enabled: Bool) {
        scanReminderEnabled = enabled
        defaults.set(enabled, forKey: Keys.scanReminderEnabled)
        reminderTask?.cancel()
        reminderTask = nil
        scanReminderError = nil

        if enabled {
            startReminderScheduling()
        } else {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [Self.reminderIdentifier])
        }
    }

    private func startReminderScheduling() {
        reminderTask = Task { [weak self] in
            await self?.scheduleReminder()
        }
    }

    private func scheduleReminder() async {
        let center = UNUserNotificationCenter.current()

        let granted: Bool
        do {
            granted = try await center.requestAuthorization(options: [.alert, .sound])
        } catch {
            failScanReminder("Cruftless could not request permission to send notifications.")
            return
        }
        guard !Task.isCancelled else { return }

        guard granted else {
            failScanReminder(
                "Notifications are turned off for Cruftless. Allow them in System Settings › Notifications."
            )
            return
        }

        let pending = await center.pendingNotificationRequests()
        guard !Task.isCancelled else { return }
        guard !pending.contains(where: { $0.identifier == Self.reminderIdentifier }) else { return }

        let content = UNMutableNotificationContent()
        content.title = "Review developer disk bloat"
        content.body = "Open Cruftless to review reclaimable Xcode and simulator files."
        content.sound = .default

        do {
            try await center.add(
                UNNotificationRequest(
                    identifier: Self.reminderIdentifier,
                    content: content,
                    trigger: UNTimeIntervalNotificationTrigger(
                        timeInterval: Self.reminderInterval,
                        repeats: true
                    )
                )
            )
        } catch {
            failScanReminder("Cruftless could not schedule the weekly reminder.")
        }
    }

    private func failScanReminder(_ message: String) {
        scanReminderEnabled = false
        defaults.set(false, forKey: Keys.scanReminderEnabled)
        scanReminderError = message
    }

    // MARK: - Protected paths

    /// Vets the folder before storing it.
    public func addProtectedPath(_ url: URL) {
        if let rejection = ProtectedPathPolicy.rejection(for: url, existing: protectedPaths) {
            protectedPathError = rejection.message
            return
        }
        protectedPathError = nil
        protectedPathsStore.addPath(url)
        protectedPaths = protectedPathsStore.customPaths()
        onProtectedPathsChanged?()
    }

    public func removeProtectedPath(_ url: URL) {
        protectedPathError = nil
        protectedPathsStore.removePath(url)
        protectedPaths = protectedPathsStore.customPaths()
        onProtectedPathsChanged?()
    }

    // MARK: - Helpers

    private static let reminderIdentifier = "cruftless.scan-reminder"
    private static let reminderInterval: TimeInterval = 7 * 24 * 60 * 60

    private enum Keys {
        static let scanReminderEnabled = "scanReminderEnabled"
    }
}

#if DEBUG
    extension SettingsModel {
        static func preview(
            protectedPaths: [URL] = [],
            launchAtLoginError: String? = nil,
            scanReminderError: String? = nil,
            protectedPathError: String? = nil
        ) -> SettingsModel {
            let suiteName = "Cruftless.SettingsPreview.\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suiteName)!
            let store = ProtectedPathsStore(userDefaults: defaults)
            for path in protectedPaths {
                store.addPath(path)
            }
            let model = SettingsModel(defaults: defaults, protectedPathsStore: store)
            model.launchAtLoginError = launchAtLoginError
            model.scanReminderError = scanReminderError
            model.protectedPathError = protectedPathError
            return model
        }
    }
#endif
