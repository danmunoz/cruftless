import Foundation

/// The weekly slot a scan reminder fires in.
public struct ScanReminderSchedule: Sendable, Equatable, Codable {
    public let weekday: Int
    public let hour: Int
    public let minute: Int

    public init(weekday: Int, hour: Int, minute: Int) {
        self.weekday = weekday
        self.hour = hour
        self.minute = minute
    }

    /// The slot one week after `date`.
    public static func starting(from date: Date, calendar: Calendar = .current) -> Self {
        let firstFire = calendar.date(byAdding: .day, value: 7, to: date) ?? date
        let parts = calendar.dateComponents([.weekday, .hour, .minute], from: firstFire)
        return Self(weekday: parts.weekday ?? 1, hour: parts.hour ?? 9, minute: parts.minute ?? 0)
    }

    public var dateComponents: DateComponents {
        DateComponents(hour: hour, minute: minute, weekday: weekday)
    }
}

public struct PendingScanReminder: Sendable, Equatable {
    public let identifier: String
    public let body: String

    public init(identifier: String, body: String) {
        self.identifier = identifier
        self.body = body
    }
}

public struct ScanReminderRequest: Sendable, Equatable {
    public let identifier: String
    public let title: String
    public let body: String
    public let schedule: ScanReminderSchedule
}

/// The notification daemon, as far as the reminder needs it.
public protocol ScanReminderCenter: Sendable {
    func requestAuthorization() async throws -> Bool
    func pendingReminders() async -> [PendingScanReminder]
    func add(_ request: ScanReminderRequest) async throws
    func removeReminder(identifier: String)
}

public enum ScanReminderOutcome: Sendable, Equatable {
    /// A matching reminder is already pending, so its countdown is left alone.
    case alreadyPending
    case scheduled(ScanReminderSchedule)
    case permissionDenied
    case authorizationFailed
    case schedulingFailed

    public var failureMessage: String? {
        switch self {
        case .alreadyPending, .scheduled:
            nil
        case .permissionDenied:
            "Notifications are turned off for Cruftless. Allow them in System Settings › Notifications."
        case .authorizationFailed:
            "Cruftless could not request permission to send notifications."
        case .schedulingFailed:
            "Cruftless could not schedule the weekly reminder."
        }
    }
}

/// Arms the weekly scan reminder without restarting a countdown that is already running.
public struct ScanReminderScheduler: Sendable {
    public static let identifier = "cruftless.scan-reminder"
    public static let title = "Review developer disk bloat"

    private let center: any ScanReminderCenter
    private let now: @Sendable () -> Date
    private let calendar: Calendar

    public init(
        center: any ScanReminderCenter,
        now: @escaping @Sendable () -> Date = { Date() },
        calendar: Calendar = .current
    ) {
        self.center = center
        self.now = now
        self.calendar = calendar
    }

    public static func body(for platforms: Set<DevelopmentPlatform>) -> String {
        if platforms == Set(DevelopmentPlatform.allCases) {
            return "Open Cruftless to review Apple and Android development storage."
        }
        return platforms.contains(.android)
            ? "Open Cruftless to review Android development storage."
            : "Open Cruftless to review Apple development storage."
    }

    /// Leaves a pending reminder with the same body untouched; otherwise schedules one in `storedSchedule`'s slot.
    public func arm(body: String, storedSchedule: ScanReminderSchedule?) async -> ScanReminderOutcome {
        let granted: Bool
        do {
            granted = try await center.requestAuthorization()
        } catch {
            return .authorizationFailed
        }
        guard granted else { return .permissionDenied }

        let pending = await center.pendingReminders()
        if pending.contains(where: { $0.identifier == Self.identifier && $0.body == body }) {
            return .alreadyPending
        }

        let schedule = storedSchedule ?? .starting(from: now(), calendar: calendar)
        do {
            try await center.add(ScanReminderRequest(
                identifier: Self.identifier,
                title: Self.title,
                body: body,
                schedule: schedule
            ))
        } catch {
            return .schedulingFailed
        }
        return .scheduled(schedule)
    }

    public func disarm() {
        center.removeReminder(identifier: Self.identifier)
    }
}
