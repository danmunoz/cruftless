import AppKit
import CruftlessCore
import Foundation
import Observation

/// One row of the uninstall review: a folder or file and what removing it means.
struct UninstallReviewRow: Identifiable, Equatable {
    let id: String
    let title: String
    let path: String
    let bytes: Int64
    let consequence: String
}

/// Drives "Remove Cruftless Data": review, removal, and the final quit.
@MainActor
@Observable
final class UninstallModel {
    enum Stage: Equatable {
        case idle
        case preparing
        case review([UninstallReviewRow])
        case refused(String)
        case removing
        case finished(UninstallReport)
    }

    /// What a removal did, step by step.
    struct UninstallReport: Equatable {
        var registrations: [UninstallStepResult]
        var files: [UninstallFileOutcome]

        var hasFailures: Bool {
            registrations.contains { $0.outcome.isFailure } || files.contains { $0.failure != nil }
        }
    }

    struct UninstallFileOutcome: Identifiable, Equatable {
        let id: String
        let title: String
        let failure: String?
    }

    /// The registrations a removal undoes, shown beside the files in review.
    static let registrationRows = [
        "Launch at Login, if it is on",
        "Scheduled scan reminders",
        "Privacy permissions macOS recorded for Cruftless",
        "Every Cruftless setting"
    ]

    /// What a removal leaves alone, stated in review.
    static let untouchedNote = """
    Nothing Cruftless already deleted can be brought back, and the developer data it tracks is not touched. \
    Cruftless.app stays where it is: drag it to the Trash after Cruftless quits.
    """

    private(set) var stage: Stage
    private let appModel: AppModel?
    private let footprint: AppFootprint
    private var plan: DeletionPlan?

    init(appModel: AppModel?, footprint: AppFootprint = .live, stage: Stage = .idle) {
        self.appModel = appModel
        self.footprint = footprint
        self.stage = stage
    }

    var isSheetPresented: Bool {
        stage != .idle
    }

    /// Plans the folder removal off the main thread and opens the review.
    func prepare() {
        guard let appModel else { return }
        guard !appModel.isDeleting else {
            stage = .refused(DeletionPlanningError.deletionInProgress.localizedDescription)
            return
        }
        stage = .preparing
        let context = PlanningContext.live(
            protectedPaths: appModel.settings.protectedPathPolicy,
            policyGeneration: appModel.settings.platformGeneration
        )
        let footprint = footprint
        Task {
            let outcome: Result<DeletionPlan, Error> = await Task.detached {
                Result { try DeletionPlanner.appFootprint(footprint, context: context) }
            }.value
            guard stage == .preparing else { return }
            switch outcome {
            case let .success(plan):
                self.plan = plan
                stage = .review(Self.rows(for: plan))
            case let .failure(error):
                stage = .refused(error.localizedDescription)
            }
        }
    }

    func cancel() {
        guard stage != .removing, !isFinished else { return }
        plan = nil
        stage = .idle
    }

    /// Stops background work for good, undoes registrations, and deletes the reviewed folders.
    func confirm() {
        guard let appModel, let plan, case .review = stage else { return }
        guard !appModel.isDeleting else {
            stage = .refused(DeletionPlanningError.deletionInProgress.localizedDescription)
            return
        }
        stage = .removing
        appModel.haltForUninstall()
        appModel.isDeleting = true
        appModel.settings.isDeletionExecuting = true
        Task {
            let registrations = await UninstallCleanup(
                bundleIdentifier: footprint.bundleIdentifier,
                loginItem: SystemLoginItemUnregistrar(),
                reminders: UserNotificationReminderCenter()
            ).run()
            let result = plan.isEmpty ? nil : await appModel.deletionExecutor.execute(plan)
            stage = .finished(UninstallReport(
                registrations: registrations,
                files: (result?.items ?? []).map {
                    UninstallFileOutcome(
                        id: $0.id,
                        title: $0.target.name,
                        failure: $0.status.failureReason ?? $0.status.notAttemptedReason
                    )
                }
            ))
        }
    }

    /// Shows the app in Finder, clears the preferences, and exits in one step, so no window can save state in between.
    func quit() {
        guard isFinished else { return }
        Self.revealBundleIfMovable()
        AppPreferences.removeAll(bundleIdentifier: footprint.bundleIdentifier)
        exit(0)
    }

    private var isFinished: Bool {
        if case .finished = stage { true } else { false }
    }

    private static func rows(for plan: DeletionPlan) -> [UninstallReviewRow] {
        plan.items.map {
            UninstallReviewRow(
                id: $0.id,
                title: $0.name,
                path: $0.validatedPath?.url.path(percentEncoded: false) ?? "",
                bytes: $0.reclaimableBytes,
                consequence: $0.consequence
            )
        }
    }

    /// Selects the bundle in Finder unless it runs from a translocated or read-only copy the user cannot trash.
    private static func revealBundleIfMovable() {
        let bundle = Bundle.main.bundleURL
        let isReadOnly = (try? bundle.resourceValues(forKeys: [.volumeIsReadOnlyKey]))?.volumeIsReadOnly ?? false
        guard !bundle.path.contains("/AppTranslocation/"), !isReadOnly else { return }
        NSWorkspace.shared.activateFileViewerSelecting([bundle])
    }
}

extension AppModel {
    /// Stops every scan, watch, timer and reminder so nothing rewrites the app's data during a removal.
    func haltForUninstall() {
        isUninstalling = true
        launchScanTask?.cancel()
        launchScanTask = nil
        powerStateTask?.cancel()
        powerStateTask = nil
        throttleWake?.cancel()
        throttleWake = nil
        prepareTask?.cancel()
        androidPreparationTask?.cancel()
        invalidator?.stopMonitoring()
        settings.haltForUninstall()
    }
}
