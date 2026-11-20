@testable import CruftlessCore
import CruftlessFixtures
import Foundation
import Testing

@Suite("Uninstall cleanup of system registrations")
struct UninstallCleanupTests {
    private struct Failure: LocalizedError {
        let errorDescription: String?
    }

    private final class Log: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [String] = []

        func append(_ entry: String) {
            lock.withLock { entries.append(entry) }
        }

        var all: [String] {
            lock.withLock { entries }
        }
    }

    private struct LoginItem: LoginItemUnregistering {
        let log: Log
        let result: Result<Bool, Failure>

        func unregisterIfRegistered() async throws -> Bool {
            log.append("loginItem")
            return try result.get()
        }
    }

    private struct Reminders: ReminderClearing {
        let log: Log

        func removeAllReminders() async {
            log.append("reminders")
        }
    }

    private struct Grants: PrivacyGrantResetting {
        let log: Log
        let failure: Failure?

        func resetAll(bundleIdentifier: String) async throws {
            log.append("grants:\(bundleIdentifier)")
            if let failure { throw failure }
        }
    }

    private struct LedgerFixture {
        let scratch = ScratchDefaults()
        let defaults: UserDefaults
        let ledger: AccessLedger

        init() throws {
            defaults = scratch.defaults
            ledger = AccessLedger(userDefaults: defaults)
            ledger.markAsked(.documents)
            ledger.markAsked(.desktop)
        }

        func remove() {
            TestFileSystem.remove(scratch)
        }
    }

    @Test("Every step runs in order and reports its own outcome")
    func runsEveryStep() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = fixture.ledger
        let log = Log()
        let cleanup = UninstallCleanup(
            bundleIdentifier: "com.example.app",
            loginItem: LoginItem(log: log, result: .success(true)),
            reminders: Reminders(log: log),
            privacyGrants: Grants(log: log, failure: nil),
            accessLedger: ledger
        )

        let results = await cleanup.run()

        #expect(log.all == ["loginItem", "reminders", "grants:com.example.app"])
        #expect(results.map(\.step) == [.loginItem, .reminders, .privacyGrants])
        #expect(results.map(\.outcome) == [.done, .done, .done])
        #expect(ledger.askedAreas().isEmpty)
    }

    @Test("A failing step never stops the ones after it")
    func neverAbortsEarly() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = fixture.ledger
        let log = Log()
        let cleanup = UninstallCleanup(
            loginItem: LoginItem(log: log, result: .failure(Failure(errorDescription: "login refused"))),
            reminders: Reminders(log: log),
            privacyGrants: Grants(log: log, failure: Failure(errorDescription: "tcc refused")),
            accessLedger: ledger
        )

        let results = await cleanup.run()

        #expect(log.all.count == 3)
        #expect(results.map(\.outcome) == [.failed("login refused"), .done, .failed("tcc refused")])
        #expect(ledger.askedAreas().isEmpty, "a failed reset still forgets every asked area")
    }

    @Test("No login item registered is nothing to do, not a failure")
    func noLoginItem() async throws {
        let fixture = try LedgerFixture()
        defer { fixture.remove() }
        let ledger = fixture.ledger
        let log = Log()
        let results = await UninstallCleanup(
            loginItem: LoginItem(log: log, result: .success(false)),
            reminders: Reminders(log: log),
            privacyGrants: Grants(log: log, failure: nil),
            accessLedger: ledger
        ).run()

        #expect(results.first?.outcome == .nothingToDo)
    }

    @Test("tccutil reports an unknown bundle identifier as a failure with its own message")
    func tccutilUnknownBundle() async {
        let resetter = TCCUtilPrivacyGrantResetter()
        await #expect(throws: TCCUtilPrivacyGrantResetter.ResetError.self) {
            try await resetter.resetAll(bundleIdentifier: "com.example.cruftless.not-installed.\(UUID().uuidString)")
        }
    }
}
