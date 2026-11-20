#if DEBUG
    import CruftlessCore
    import Foundation

    /// Uninstall states for previews; none of them touch the real footprint.
    @MainActor
    enum UninstallPreviewFixtures {
        static func model(_ stage: UninstallModel.Stage) -> UninstallModel {
            UninstallModel(appModel: nil, stage: stage)
        }

        static let rows = [
            UninstallReviewRow(
                id: "app-footprint-application-support",
                title: "Saved scan and Android tools",
                path: "/Users/daniel/Library/Application Support/Cruftless",
                bytes: 48_000_000,
                consequence: "The last scan is forgotten and the Android command-line tools Cruftless downloaded are removed."
            ),
            UninstallReviewRow(
                id: "app-footprint-caches",
                title: "Caches",
                path: "/Users/daniel/Library/Caches/com.danmunoz.Cruftless",
                bytes: 212_992,
                consequence: "Cached update-check responses are removed."
            ),
            UninstallReviewRow(
                id: "app-footprint-user-cache",
                title: "System cache",
                path: "/private/var/folders/qv/example/C/com.danmunoz.Cruftless",
                bytes: 339_968,
                consequence: "Graphics caches macOS kept for Cruftless are removed."
            )
        ]

        static let refusal = DeletionPlanningError.deletionInProgress.localizedDescription

        static let cleanReport = UninstallModel.UninstallReport(
            registrations: [
                UninstallStepResult(step: .loginItem, outcome: .done),
                UninstallStepResult(step: .reminders, outcome: .done),
                UninstallStepResult(step: .privacyGrants, outcome: .done)
            ],
            files: rows.map { UninstallModel.UninstallFileOutcome(id: $0.id, title: $0.title, failure: nil) }
        )

        static let failedReport = UninstallModel.UninstallReport(
            registrations: [
                UninstallStepResult(step: .loginItem, outcome: .nothingToDo),
                UninstallStepResult(step: .reminders, outcome: .done),
                UninstallStepResult(step: .privacyGrants, outcome: .failed("tccutil exited with status 64."))
            ],
            files: [
                UninstallModel.UninstallFileOutcome(id: "a", title: "Saved scan and Android tools", failure: nil),
                UninstallModel.UninstallFileOutcome(id: "b", title: "Caches", failure: "Permission denied.")
            ]
        )
    }
#endif
