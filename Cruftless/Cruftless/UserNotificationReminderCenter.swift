import CruftlessCore
import UserNotifications

/// Backs the scan reminder with the system notification daemon.
public struct UserNotificationReminderCenter: ScanReminderCenter {
    public init() {}

    public func requestAuthorization() async throws -> Bool {
        try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound])
    }

    public func pendingReminders() async -> [PendingScanReminder] {
        await UNUserNotificationCenter.current().pendingNotificationRequests().map {
            PendingScanReminder(identifier: $0.identifier, body: $0.content.body)
        }
    }

    public func add(_ request: ScanReminderRequest) async throws {
        let content = UNMutableNotificationContent()
        content.title = request.title
        content.body = request.body
        content.sound = .default
        try await UNUserNotificationCenter.current().add(UNNotificationRequest(
            identifier: request.identifier,
            content: content,
            trigger: UNCalendarNotificationTrigger(dateMatching: request.schedule.dateComponents, repeats: true)
        ))
    }

    public func removeReminder(identifier: String) {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [identifier])
    }
}
