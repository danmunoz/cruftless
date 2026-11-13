@testable import CruftlessCore
import Foundation
import ServiceManagement
import Testing

@Suite("Launch at login messages")
struct LaunchAtLoginPolicyTests {
    @Test("Enabling into .requiresApproval reports the approval step, not success")
    func requiresApprovalIsReported() {
        let message = LaunchAtLoginPolicy.message(requested: true, status: .requiresApproval, failure: nil)
        #expect(message?.contains("Login Items") == true)
    }

    @Test("Enabling that actually landed reports nothing")
    func enabledIsSilent() {
        #expect(LaunchAtLoginPolicy.message(requested: true, status: .enabled) == nil)
    }

    @Test("A registration left unfound outside Applications names the move")
    func notFoundOutsideApplications() {
        let message = LaunchAtLoginPolicy.message(requested: true, status: .notFound, isInApplicationsFolder: false)
        #expect(message?.contains("Move Cruftless to Applications") == true)
    }

    @Test("A registration left unfound inside Applications never asks for a move")
    func notFoundInsideApplications() {
        let message = LaunchAtLoginPolicy.message(requested: true, status: .notFound, isInApplicationsFolder: true)
        #expect(message?.contains("Move Cruftless") == false)
        #expect(message?.contains("Login Items") == true)
        #expect(LaunchAtLoginPolicy.offersLoginItemsSettings(status: .notFound, hasFailure: true))
    }

    @Test("A thrown failure is surfaced when the status says nothing more specific")
    func thrownFailureSurfaces() {
        let message = LaunchAtLoginPolicy.message(
            requested: true,
            status: .notRegistered,
            failure: "Operation not permitted"
        )
        #expect(message == "Operation not permitted")
    }

    @Test("Disabling something already off is not an error, even when it threw")
    func disableThatThrewButReachedGoalState() {
        #expect(LaunchAtLoginPolicy.message(requested: false, status: .notRegistered, failure: "boom") == nil)
    }

    @Test("Disabling that left the item enabled is an error")
    func disableThatFailed() {
        #expect(LaunchAtLoginPolicy.message(requested: false, status: .enabled, failure: nil) != nil)
    }
}

@Suite("Launch at login status")
struct LaunchAtLoginStatusTests {
    @Test("Pending approval explains itself without any toggle attempt")
    func approvalIsExplainedFromStatusAlone() {
        let message = LaunchAtLoginPolicy.statusMessage(for: .requiresApproval)
        #expect(message?.contains("Login Items") == true)
        #expect(LaunchAtLoginPolicy.needsApproval(.requiresApproval))
    }

    @Test(
        "States seen before any toggle attempt need no explanation",
        arguments: [SMAppService.Status.enabled, .notRegistered, .notFound]
    )
    func untouchedStatesAreSilent(status: SMAppService.Status) {
        #expect(LaunchAtLoginPolicy.statusMessage(for: status) == nil)
        #expect(!LaunchAtLoginPolicy.needsApproval(status))
        #expect(!LaunchAtLoginPolicy.offersLoginItemsSettings(status: status, hasFailure: false))
    }

    @Test("An installed copy is recognised in either Applications folder")
    func applicationsFolderDetection() {
        let home = URL(fileURLWithPath: "/Users/someone", isDirectory: true)
        let check = { LaunchAtLoginPolicy.isInApplicationsFolder(URL(fileURLWithPath: $0), home: home) }
        #expect(check("/Applications/Cruftless.app"))
        #expect(check("/Users/someone/Applications/Cruftless.app"))
        #expect(!check("/Users/someone/Downloads/Cruftless.app"))
        #expect(!check("/ApplicationsExtra/Cruftless.app"))
    }

    @Test("A write that lands in a status with its own explanation adds no second message")
    func writeFailureDefersToStatus() {
        #expect(LaunchAtLoginPolicy.failureMessage(requested: true, status: .requiresApproval) == nil)
    }

    @Test("A write failure the status cannot explain is still reported")
    func writeFailureSurfaces() {
        #expect(
            LaunchAtLoginPolicy.failureMessage(requested: true, status: .notRegistered, failure: "denied") == "denied"
        )
        #expect(LaunchAtLoginPolicy.failureMessage(requested: false, status: .enabled) != nil)
    }
}

@Suite("Folder picker failures")
struct FolderPickerFailureTests {
    @Test("Cancelling the picker is silent")
    func cancelIsSilent() {
        #expect(ProtectedPathPolicy.pickerFailureMessage(for: CocoaError(.userCancelled)) == nil)
    }

    @Test("Any other picker error is reported")
    func otherErrorsAreReported() {
        #expect(ProtectedPathPolicy.pickerFailureMessage(for: CocoaError(.fileReadNoPermission)) != nil)
    }
}

@Suite("Settings control policy")
struct SettingsControlPolicyTests {
    private let both = PlatformSelection.all

    @Test("The only selected platform cannot be turned off")
    func lastPlatformIsLocked() {
        #expect(SettingsControlPolicy.isPlatformToggleDisabled(.apple, selection: .appleOnly, isDeletionExecuting: false))
        #expect(!SettingsControlPolicy.isPlatformToggleDisabled(.android, selection: .appleOnly, isDeletionExecuting: false))
        #expect(!SettingsControlPolicy.isPlatformToggleDisabled(.apple, selection: both, isDeletionExecuting: false))
    }

    @Test("A running deletion locks every platform toggle")
    func deletionLocksToggles() {
        for platform in DevelopmentPlatform.allCases {
            #expect(SettingsControlPolicy.isPlatformToggleDisabled(platform, selection: both, isDeletionExecuting: true))
        }
    }

    @Test("Turning a platform on or off yields the new selection")
    func togglingUpdatesSelection() {
        #expect(SettingsControlPolicy.updatedSelection(from: both, platform: .android, enabled: false) == .appleOnly)
        #expect(SettingsControlPolicy.updatedSelection(from: .appleOnly, platform: .android, enabled: true) == both)
    }

    @Test("Removing the last platform or repeating a state changes nothing")
    func refusedAndNoOpChanges() {
        #expect(SettingsControlPolicy.updatedSelection(from: .appleOnly, platform: .apple, enabled: false) == nil)
        #expect(SettingsControlPolicy.updatedSelection(from: .appleOnly, platform: .android, enabled: false) == nil)
        #expect(SettingsControlPolicy.updatedSelection(from: both, platform: .apple, enabled: true) == nil)
    }

    @Test("The order picker shows only when both platforms are listed")
    func orderPickerVisibility() {
        #expect(SettingsControlPolicy.showsPlatformOrder(for: both))
        #expect(!SettingsControlPolicy.showsPlatformOrder(for: .androidOnly))
    }

    @Test("Protected path edits lock during a deletion")
    func protectedPathEdits() {
        #expect(SettingsControlPolicy.allowsProtectedPathEdits(isDeletionExecuting: false))
        #expect(!SettingsControlPolicy.allowsProtectedPathEdits(isDeletionExecuting: true))
    }

    @Test("Busy messages clear when the deletion ends; other messages stay")
    func busyMessagesClear() {
        #expect(SettingsControlPolicy.clearingBusyMessage(SettingsControlPolicy.platformSelectionBusyMessage) == nil)
        #expect(SettingsControlPolicy.clearingBusyMessage(SettingsControlPolicy.protectedPathsBusyMessage) == nil)
        #expect(SettingsControlPolicy.clearingBusyMessage("Already covered by ~/Dev.") == "Already covered by ~/Dev.")
        #expect(SettingsControlPolicy.clearingBusyMessage(nil) == nil)
    }
}

@Suite("Protected path admission")
struct ProtectedPathPolicyTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test("The volume root is refused")
    func volumeRoot() {
        #expect(
            ProtectedPathPolicy.rejection(for: URL(fileURLWithPath: "/"), home: home) == .volumeRoot
        )
    }

    @Test("The home directory is refused: it is already protected")
    func homeDirectory() {
        #expect(ProtectedPathPolicy.rejection(for: home, home: home) == .homeDirectory)
    }

    @Test("A folder under an entry already listed is refused as redundant")
    func nestedUnderExisting() {
        let existing = [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Dev/App", isDirectory: true),
            home: home,
            existing: existing
        )
        #expect(rejection == .alreadyCovered(ancestor: "~/Dev"))
    }

    @Test("A sibling sharing a name prefix is not treated as nested")
    func siblingPrefixIsNotNested() {
        let existing = [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Development", isDirectory: true),
            home: home,
            existing: existing
        )
        #expect(rejection == nil)
    }

    @Test("An unrelated folder is admitted")
    func admitted() {
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Archive", isDirectory: true),
            home: home,
            existing: [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        )
        #expect(rejection == nil)
    }

    @Test("A trailing slash does not disguise a duplicate")
    func trailingSlashDuplicate() {
        let existing = [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Dev/", isDirectory: true),
            home: home,
            existing: existing
        )
        #expect(rejection == .alreadyCovered(ancestor: "~/Dev"))
    }
}

@Suite("Version display")
struct CruftlessVersionTests {
    @Test("Short version and build render together")
    func shortAndBuild() {
        #expect(CruftlessVersion.display(shortVersion: "1.2", build: "34") == "Version 1.2 (34)")
    }

    @Test("A build that duplicates the short version is not repeated")
    func duplicateBuild() {
        #expect(CruftlessVersion.display(shortVersion: "1.0", build: "1.0") == "Version 1.0")
    }

    @Test("A missing build still renders a version")
    func missingBuild() {
        #expect(CruftlessVersion.display(shortVersion: "1.0", build: nil) == "Version 1.0")
        #expect(CruftlessVersion.display(shortVersion: "1.0", build: "  ") == "Version 1.0")
    }

    @Test("A bundle carrying neither key renders nothing")
    func nothingToShow() {
        #expect(CruftlessVersion.display(shortVersion: nil, build: nil) == nil)
    }
}
