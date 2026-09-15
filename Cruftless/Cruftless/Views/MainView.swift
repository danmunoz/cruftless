import AppKit
import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// The popover root and the owner of the push stack.
public struct MainView: View {
    @Bindable public var model: AppModel
    @Environment(\.openSettings) private var openSettings

    /// The natural height `ReviewView`/`ResultView` last reported through `ContentHeightPreference`.
    @State private var reportedContentHeight: CGFloat = PopoverMetrics.height

    public init(model: AppModel) {
        self.model = model
    }

    public var body: some View {
        NavigationStack(path: $model.navigationPath) {
            ListView(model: model, onOpenSettings: openSettingsWindow)
                .popoverScreen()
                .navigationDestination(for: AppRoute.self, destination: screen)
        }
        .frame(width: PopoverMetrics.width, height: resolvedHeight)
        .onPreferenceChange(ContentHeightPreference.self) { reportedContentHeight = $0 }
        .animation(PopoverMetrics.pushAnimation, value: resolvedHeight)
        .onDisappear {
            model.cancelPreparation()
            model.popToRoot()
        }
    }

    /// The pushed screen for a route.
    private func screen(for route: AppRoute) -> some View {
        destination(for: route).popoverScreen()
    }

    @ViewBuilder
    private func destination(for route: AppRoute) -> some View {
        switch route {
        case let .detail(location):
            DetailScreen(location: location, model: model, backTitle: backTitle(under: route))

        case let .review(plan):
            ReviewView(
                plan: plan,
                backTitle: backTitle(under: route),
                runningAppsWarning: model.runningAppsWarning,
                isExecuting: model.isDeleting,
                onConfirm: { await model.executeDeletion(plan: plan) },
                onCancel: model.pop
            )

        case let .result(result):
            ResultView(
                result: result,
                freeSpaceDelta: model.freeSpaceDelta,
                onDone: model.popToRoot
            )
        }
    }

    private var resolvedHeight: CGFloat {
        switch model.navigationPath.last {
        case .review, .result:
            min(max(reportedContentHeight, PopoverMetrics.contentMinHeight), PopoverMetrics.height)
        case nil, .detail:
            PopoverMetrics.height
        }
    }

    /// Title of the screen below `route`: what its back control returns to.
    private func backTitle(under route: AppRoute) -> String {
        let parent = model.navigationPath.firstIndex(of: route)
            .flatMap { $0 > 0 ? model.navigationPath[$0 - 1] : nil }
        return switch parent {
        case nil: "Overview"
        case let .detail(location): location.title
        case .review: "Review"
        case .result: "Result"
        }
    }

    private func openSettingsWindow() {
        openSettings()
        NSApp.activate()
    }
}

/// Routes a `Detail` push to the presentation that location needs.
private struct DetailScreen: View {
    let location: TrackedLocation
    @Bindable var model: AppModel
    let backTitle: String

    var body: some View {
        switch location.id {
        case LocationCatalog.simulatorDevices.id:
            SimulatorsDetailView(location: location, model: model, backTitle: backTitle)
        case LocationCatalog.simulatorRuntimes.id:
            RuntimesDetailView(location: location, model: model, backTitle: backTitle)
        default:
            DetailView(location: location, model: model, backTitle: backTitle)
        }
    }
}

struct ContentHeightPreference: PreferenceKey {
    static let defaultValue: CGFloat = PopoverMetrics.height
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = nextValue()
    }
}

/// Reports a view's actual rendered height into `height`, without affecting its own layout.
private struct HeightReader: ViewModifier {
    @Binding var height: CGFloat

    func body(content: Content) -> some View {
        content.background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear { height = proxy.size.height }
                    .onChange(of: proxy.size.height) { _, newValue in height = newValue }
            }
        }
    }
}

extension View {
    func measuringHeight(into height: Binding<CGFloat>) -> some View {
        modifier(HeightReader(height: height))
    }

    /// Makes a view a screen in the popover's stack: opaque to the screen it slides over, and without the stack's own chrome.
    func popoverScreen() -> some View {
        background { Rectangle().fill(.ultraThinMaterial) }
            .navigationBarBackButtonHidden(true)
            .toolbarVisibility(.hidden, for: .windowToolbar)
    }
}

#if DEBUG
    #Preview("Popover") {
        MainView(model: AppModel())
    }

    #Preview("Popover: Populated list") {
        MainView(model: .previewPopulated())
    }

    #Preview("Popover: Detail pushed") {
        let model = AppModel.previewDrillDown(
            .children(PreviewFixtures.sampleChildren),
            for: LocationCatalog.derivedData.id
        )
        model.navigationPath = [.detail(LocationCatalog.derivedData)]
        return MainView(model: model)
    }
#endif
