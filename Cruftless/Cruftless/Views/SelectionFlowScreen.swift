import CruftlessCore
import SwiftUI

enum SelectionScreen {
    case risk(ChildEntry)
    case review
    case result
}

struct SelectionFlowScreen: View {
    let location: TrackedLocation
    let screen: SelectionScreen
    let model: AppModel
    var isPreviewFixture = false

    var body: some View {
        Group {
            if let session = model.cleanupSessions[location.id] {
                SelectionSessionScreen(
                    screen: screen, model: model, session: session, isPreviewFixture: isPreviewFixture
                )
            } else {
                ProgressView("Preparing selection…")
            }
        }
        .task {
            guard !isPreviewFixture else { return }
            _ = model.selectionSession(for: location)
            if let session = model.cleanupSessions[location.id], session.stage == .selection {
                model.returnToSelection(session)
            }
        }
    }
}

private struct SelectionSessionScreen: View {
    let screen: SelectionScreen
    let model: AppModel
    @Bindable var session: CleanupSelectionSession
    let isPreviewFixture: Bool

    var body: some View {
        content
            .onChange(of: model.settings.platformGeneration) { _, _ in
                guard !isPreviewFixture else { return }
                model.synchronizeSelectionSession(session)
                if session.stage == .selection { model.returnToSelection(session) }
            }
            .onChange(of: session.stage) { _, stage in
                if stage == .selection { model.returnToSelection(session) }
            }
    }

    @ViewBuilder
    private var content: some View {
        switch screen {
        case let .risk(child):
            GradleCacheRiskView(
                location: session.location, child: child, model: model, backTitle: session.location.title,
                onCancel: { model.cancelCleanupReview(in: session) },
                onAccept: { model.acceptCleanupGradleRisk(in: session, child: child) },
                notice: session.notice,
                canAccept: session.isReady && !session.isRefreshing && !isPreviewFixture
            )
        case .review:
            if let plan = session.reviewPlan {
                ReviewView(
                    plan: plan, backTitle: session.location.title, runningAppsWarning: model.runningAppsWarning,
                    isExecuting: session.stage == .executing,
                    progress: model.deletionProgress, run: model.deletionRun,
                    currentFreeBytes: session.reviewFreeSpaceBytes,
                    notice: session.notice,
                    canConfirm: session.isReady && !session.isRefreshing && !isPreviewFixture,
                    isBusy: model.isDeleting && session.stage != .executing,
                    showsActionLabels: true,
                    isStopRequested: model.isDeletionStopRequested,
                    onConfirm: { model.confirmCleanup(in: session) },
                    onCancel: { model.cancelCleanupReview(in: session) },
                    onStop: model.stopDeletionAfterCurrentItem
                )
            } else {
                PopoverPlaceholder(symbol: "checklist", title: "Nothing to review")
            }
        case .result:
            if let result = session.result {
                ResultView(result: result, freeSpaceDelta: session.freeSpaceDelta) {
                    if isPreviewFixture {
                        session.result = nil
                        session.selection.clear()
                        session.stage = .selection
                        model.returnToSelection(session)
                    } else {
                        model.finishSelection(session)
                    }
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Selection: mixed review") {
        let model = CleanupSelectionPreviewFixtures.mixedSimulatorModel()
        SelectionFlowScreen(location: LocationCatalog.simulatorDevices, screen: .review, model: model, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: executing") {
        let model = CleanupSelectionPreviewFixtures.executingModel()
        SelectionFlowScreen(location: LocationCatalog.simulatorDevices, screen: .review, model: model, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: partial result") {
        let model = CleanupSelectionPreviewFixtures.partialResultModel()
        SelectionFlowScreen(location: LocationCatalog.simulatorDevices, screen: .result, model: model, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
