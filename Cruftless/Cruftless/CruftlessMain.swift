import CruftlessCore
import Foundation
import SwiftUI

/// Starts the app, or runs the headless uninstall cleanup when asked to by exactly one argument.
@main
enum CruftlessMain {
    static let uninstallCleanupArgument = "--uninstall-cleanup"

    @MainActor
    static func main() {
        if CommandLine.arguments.dropFirst().elementsEqual([uninstallCleanupArgument]) {
            HeadlessUninstall.run()
        }
        CruftlessApp.main()
    }
}

/// Undoes the app's system registrations and preferences without any UI, then exits 0.
///
/// Homebrew's `zap` runs this before it removes the bundle; files are left to the cask's `trash` list.
@MainActor
enum HeadlessUninstall {
    static let deadline: DispatchTimeInterval = .seconds(10)

    static func run() -> Never {
        DispatchQueue.global().asyncAfter(deadline: .now() + deadline) {
            print("Cruftless: uninstall cleanup timed out")
            exit(0)
        }
        Task { @MainActor in
            let results = await UninstallCleanup(
                loginItem: SystemLoginItemUnregistrar(),
                reminders: UserNotificationReminderCenter()
            ).run()
            for result in results {
                print("Cruftless: \(result.step.title): \(result.outcome.summary)")
            }
            AppPreferences.removeAll()
            print("Cruftless: Preferences: removed")
            exit(0)
        }
        dispatchMain()
    }
}

/// The app's own preferences domain.
enum AppPreferences {
    /// Removes the whole domain and writes the removal through before the process exits.
    static func removeAll(bundleIdentifier: String = AppFootprint.live.bundleIdentifier) {
        UserDefaults.standard.removePersistentDomain(forName: bundleIdentifier)
        CFPreferencesAppSynchronize(bundleIdentifier as CFString)
    }
}

extension UninstallStepOutcome {
    var summary: String {
        switch self {
        case .done: "removed"
        case .nothingToDo: "nothing to remove"
        case let .failed(reason): "failed: \(reason)"
        }
    }
}
