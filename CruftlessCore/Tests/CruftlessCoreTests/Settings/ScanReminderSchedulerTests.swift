@testable import CruftlessCore
import Foundation
import Testing

@Suite("Scan reminder scheduling")
struct ScanReminderSchedulerTests {
    private static let body = ScanReminderScheduler.body(for: [.apple])
    private static let now = Date(timeIntervalSince1970: 1_800_000_000)

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func scheduler(_ center: FakeReminderCenter) -> ScanReminderScheduler {
        ScanReminderScheduler(center: center, now: { Self.now }, calendar: Self.calendar)
    }

    @Test("A pending reminder with the same body is left alone, so relaunching never restarts its countdown")
    func pendingReminderIsKept() async {
        let center = FakeReminderCenter(pending: [
            PendingScanReminder(identifier: ScanReminderScheduler.identifier, body: Self.body)
        ])
        let outcome = await scheduler(center).arm(body: Self.body, storedSchedule: nil)
        #expect(outcome == .alreadyPending)
        #expect(await center.added.isEmpty)
    }

    @Test("Repeated arming adds the request once")
    func repeatedArmingAddsOnce() async {
        let center = FakeReminderCenter()
        let scheduler = scheduler(center)
        let first = await scheduler.arm(body: Self.body, storedSchedule: nil)
        let second = await scheduler.arm(body: Self.body, storedSchedule: nil)
        #expect(first == .scheduled(.starting(from: Self.now, calendar: Self.calendar)))
        #expect(second == .alreadyPending)
        #expect(await center.added.count == 1)
    }

    @Test("A changed body reuses the stored weekly slot instead of starting a new week")
    func changedBodyKeepsSlot() async {
        let stored = ScanReminderSchedule(weekday: 3, hour: 14, minute: 5)
        let center = FakeReminderCenter(pending: [
            PendingScanReminder(identifier: ScanReminderScheduler.identifier, body: Self.body)
        ])
        let newBody = ScanReminderScheduler.body(for: Set(DevelopmentPlatform.allCases))
        let outcome = await scheduler(center).arm(body: newBody, storedSchedule: stored)
        #expect(outcome == .scheduled(stored))
        #expect(await center.added.map(\.schedule) == [stored])
        #expect(await center.added.map(\.body) == [newBody])
    }

    @Test("A new reminder first fires one week out")
    func firstSlotIsOneWeekOut() throws {
        let schedule = ScanReminderSchedule.starting(from: Self.now, calendar: Self.calendar)
        let expected = try #require(Self.calendar.date(byAdding: .day, value: 7, to: Self.now))
        let parts = Self.calendar.dateComponents([.weekday, .hour, .minute], from: expected)
        #expect(try schedule == ScanReminderSchedule(
            weekday: #require(parts.weekday),
            hour: #require(parts.hour),
            minute: #require(parts.minute)
        ))
    }

    @Test("Refused permission adds nothing and reports why")
    func permissionDenied() async {
        let center = FakeReminderCenter(granted: false)
        let outcome = await scheduler(center).arm(body: Self.body, storedSchedule: nil)
        #expect(outcome == .permissionDenied)
        #expect(outcome.failureMessage?.contains("System Settings") == true)
        #expect(await center.added.isEmpty)
    }

    @Test("A failed authorization request is reported")
    func authorizationFailure() async {
        let center = FakeReminderCenter(authorizationThrows: true)
        #expect(await scheduler(center).arm(body: Self.body, storedSchedule: nil) == .authorizationFailed)
    }

    @Test("A failed add is reported")
    func addFailure() async {
        let center = FakeReminderCenter(addThrows: true)
        #expect(await scheduler(center).arm(body: Self.body, storedSchedule: nil) == .schedulingFailed)
    }

    @Test("Another app reminder with the same body does not count as pending")
    func otherIdentifierIgnored() async {
        let center = FakeReminderCenter(pending: [PendingScanReminder(identifier: "other", body: Self.body)])
        let outcome = await scheduler(center).arm(body: Self.body, storedSchedule: nil)
        #expect(outcome == .scheduled(.starting(from: Self.now, calendar: Self.calendar)))
    }

    @Test("Disarming removes the reminder identifier")
    func disarmRemoves() async {
        let center = FakeReminderCenter(pending: [
            PendingScanReminder(identifier: ScanReminderScheduler.identifier, body: Self.body)
        ])
        scheduler(center).disarm()
        #expect(await center.pendingReminders().isEmpty)
    }

    @Test("Permission revoked after enabling is reported as denied")
    func revokedPermissionIsDetected() async {
        let center = FakeReminderCenter(authorization: .denied)
        #expect(await scheduler(center).checkPermission() == .permissionDenied)
    }

    @Test("Granted or undecided permission needs no action")
    func undeniedPermissionIsSilent() async {
        for status in [ScanReminderAuthorization.authorized, .notDetermined] {
            let center = FakeReminderCenter(authorization: status)
            #expect(await scheduler(center).checkPermission() == nil)
        }
    }

    @Test("Checking permission never prompts or schedules")
    func checkingPermissionHasNoSideEffects() async {
        let center = FakeReminderCenter(authorization: .denied)
        _ = await scheduler(center).checkPermission()
        #expect(await center.added.isEmpty)
        #expect(await center.authorizationRequests == 0)
    }

    @Test("Bodies name the selected platforms")
    func bodies() {
        #expect(ScanReminderScheduler.body(for: [.apple]).contains("Apple development"))
        #expect(ScanReminderScheduler.body(for: [.android]).contains("Android development"))
        #expect(ScanReminderScheduler.body(for: Set(DevelopmentPlatform.allCases)).contains("Apple and Android"))
    }
}

private final class FakeReminderCenter: ScanReminderCenter, @unchecked Sendable {
    private let lock = NSLock()
    private var pending: [PendingScanReminder]
    private var addedRequests: [ScanReminderRequest] = []
    private let granted: Bool
    private let authorizationThrows: Bool
    private let addThrows: Bool
    private let authorization: ScanReminderAuthorization
    private var requestCount = 0

    init(
        pending: [PendingScanReminder] = [],
        granted: Bool = true,
        authorizationThrows: Bool = false,
        addThrows: Bool = false,
        authorization: ScanReminderAuthorization = .authorized
    ) {
        self.authorization = authorization
        self.pending = pending
        self.granted = granted
        self.authorizationThrows = authorizationThrows
        self.addThrows = addThrows
    }

    var added: [ScanReminderRequest] {
        get async { lock.withLock { addedRequests } }
    }

    var authorizationRequests: Int {
        get async { lock.withLock { requestCount } }
    }

    func authorizationStatus() async -> ScanReminderAuthorization {
        authorization
    }

    func requestAuthorization() async throws -> Bool {
        lock.withLock { requestCount += 1 }
        if authorizationThrows { throw CocoaError(.featureUnsupported) }
        return granted
    }

    func pendingReminders() async -> [PendingScanReminder] {
        lock.withLock { pending }
    }

    func add(_ request: ScanReminderRequest) async throws {
        if addThrows { throw CocoaError(.featureUnsupported) }
        lock.withLock {
            pending.removeAll { $0.identifier == request.identifier }
            pending.append(PendingScanReminder(identifier: request.identifier, body: request.body))
            addedRequests.append(request)
        }
    }

    func removeReminder(identifier: String) {
        lock.withLock { pending.removeAll { $0.identifier == identifier } }
    }
}
