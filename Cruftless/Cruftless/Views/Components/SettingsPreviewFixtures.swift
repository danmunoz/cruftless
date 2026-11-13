#if DEBUG
    import CruftlessCore
    import Foundation
    import ServiceManagement

    /// A login item whose status never changes, so previews do not touch the real registration.
    struct FixedLoginItemService: LoginItemService {
        let status: SMAppService.Status

        func register() throws {}
        func unregister() throws {}
        func openSystemSettings() {}
    }

    enum SettingsPreviewFixtures {
        static let protectedPaths = [
            URL(fileURLWithPath: "/Users/daniel/Developer/ImportantProject"),
            URL(fileURLWithPath: "/Users/daniel/Desktop/ReleaseArtifacts")
        ]

        static let launchAtLoginFailure = "Cruftless could not be registered to launch at login."
        static let notificationsOff = "Notifications are turned off for Cruftless. "
            + "Allow them in System Settings › Notifications."

        @MainActor
        static var deletionRunning: SettingsModel {
            .preview(protectedPaths: protectedPaths, isDeletionExecuting: true)
        }

        @MainActor
        static var platformSelectionRefused: SettingsModel {
            .preview(
                platformSelectionError: SettingsControlPolicy.platformSelectionBusyMessage,
                isDeletionExecuting: true
            )
        }

        @MainActor
        static var pendingApproval: SettingsModel {
            .preview(launchAtLoginStatus: .requiresApproval)
        }

        @MainActor
        static var errors: SettingsModel {
            .preview(
                launchAtLoginError: launchAtLoginFailure,
                scanReminderError: notificationsOff,
                protectedPathError: ProtectedPathRejection.volumeRoot.message
            )
        }
    }
#endif
