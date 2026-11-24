import Foundation

/// Removes the app's login item.
public protocol LoginItemUnregistering: Sendable {
    /// Returns whether a registration existed.
    func unregisterIfRegistered() async throws -> Bool
}

/// Removes every scan reminder the app scheduled or delivered.
public protocol ReminderClearing: Sendable {
    func removeAllReminders() async
}

/// Resets the privacy decisions macOS recorded for a bundle.
public protocol PrivacyGrantResetting: Sendable {
    func resetAll(bundleIdentifier: String) async throws
}

/// Resets privacy decisions with `/usr/bin/tccutil`.
public struct TCCUtilPrivacyGrantResetter: PrivacyGrantResetting {
    public enum ResetError: Error, Equatable, LocalizedError {
        case failed(status: Int32, message: String)

        public var errorDescription: String? {
            switch self {
            case let .failed(status, message):
                message.isEmpty ? "tccutil exited with status \(status)." : message
            }
        }
    }

    static let executable = URL(fileURLWithPath: "/usr/bin/tccutil")
    private let timeout: Duration

    public init(timeout: Duration = .seconds(5)) {
        self.timeout = timeout
    }

    public func resetAll(bundleIdentifier: String) async throws {
        let output = try await BoundedProcess.run(
            executable: Self.executable,
            arguments: ["reset", "All", bundleIdentifier],
            environment: BoundedProcess.minimalEnvironment(),
            timeout: timeout
        )
        guard output.status == 0 else {
            throw ResetError.failed(
                status: output.status,
                message: output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            )
        }
    }
}

/// One system registration a removal undoes.
public enum UninstallStep: String, Sendable, CaseIterable {
    case loginItem
    case reminders
    case privacyGrants

    public var title: String {
        switch self {
        case .loginItem: "Login item"
        case .reminders: "Scan reminders"
        case .privacyGrants: "Privacy permissions"
        }
    }
}

/// What happened to one step.
public enum UninstallStepOutcome: Sendable, Equatable {
    case done
    case nothingToDo
    case failed(String)

    public var isFailure: Bool {
        if case .failed = self { true } else { false }
    }
}

public struct UninstallStepResult: Sendable, Equatable, Identifiable {
    public let step: UninstallStep
    public let outcome: UninstallStepOutcome

    public var id: UninstallStep { step }

    public init(step: UninstallStep, outcome: UninstallStepOutcome) {
        self.step = step
        self.outcome = outcome
    }
}

/// Undoes the registrations Cruftless makes with macOS: login item, reminders, and privacy grants.
public struct UninstallCleanup: Sendable {
    private let bundleIdentifier: String
    private let loginItem: any LoginItemUnregistering
    private let reminders: any ReminderClearing
    private let privacyGrants: any PrivacyGrantResetting
    private let accessLedger: AccessLedger

    public init(
        bundleIdentifier: String = AppFootprint.defaultBundleIdentifier,
        loginItem: any LoginItemUnregistering,
        reminders: any ReminderClearing,
        privacyGrants: any PrivacyGrantResetting = TCCUtilPrivacyGrantResetter(),
        accessLedger: AccessLedger = .shared
    ) {
        self.bundleIdentifier = bundleIdentifier
        self.loginItem = loginItem
        self.reminders = reminders
        self.privacyGrants = privacyGrants
        self.accessLedger = accessLedger
    }

    /// Runs every step, whatever an earlier one returned.
    public func run() async -> [UninstallStepResult] {
        var results: [UninstallStepResult] = []
        for step in UninstallStep.allCases {
            await results.append(UninstallStepResult(step: step, outcome: perform(step)))
        }
        return results
    }

    private func perform(_ step: UninstallStep) async -> UninstallStepOutcome {
        switch step {
        case .loginItem:
            do {
                return try await loginItem.unregisterIfRegistered() ? .done : .nothingToDo
            } catch {
                return .failed(error.localizedDescription)
            }
        case .reminders:
            await reminders.removeAllReminders()
            return .done
        case .privacyGrants:
            // The ledger is cleared even on failure: an area it forgets is asked about again, never opened unasked.
            defer { accessLedger.clearAll() }
            do {
                try await privacyGrants.resetAll(bundleIdentifier: bundleIdentifier)
                return .done
            } catch {
                return .failed(error.localizedDescription)
            }
        }
    }
}
