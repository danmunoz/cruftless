import CruftlessCore
import SwiftUI

/// Drill-down for installed simulator runtimes.
public struct RuntimesDetailView: View {
    public let location: TrackedLocation
    @Bindable public var model: AppModel
    public let backTitle: String

    @State private var pinned: DrillDownContent?

    public init(location: TrackedLocation, model: AppModel, backTitle: String = "Overview") {
        self.location = location
        self.model = model
        self.backTitle = backTitle
        _pinned = State(initialValue: model.drillDowns[location.id])
    }

    private var contents: DrillDownContent? {
        model.isNavigating ? pinned : model.drillDowns[location.id]
    }

    private var runtimes: [SimRuntime] {
        contents?.runtimes ?? []
    }

    public var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: location.title, backTitle: backTitle, onBack: model.pop)
            Hairline()

            LoadStateView(
                isLoading: contents == nil,
                loadingTitle: "Reading runtimes…",
                error: contents?.failureReason,
                errorTitle: "Couldn't read runtimes",
                isEmpty: runtimes.isEmpty,
                emptySymbol: "square.stack.3d.up.slash",
                emptyTitle: "No runtimes",
                emptyMessage: "No downloadable simulator runtimes are installed.",
                retry: { model.reloadDrillDown(for: location) },
                content: { content }
            )
        }
    }

    private func planDelete(_ runtime: SimRuntime) {
        model.plan { context in
            try DeletionPlanner.runtimeDelete(runtime, context: context)
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(runtimes) { runtime in
                    PopoverRow(
                        icon: .symbol("square.stack.3d.up"),
                        title: runtime.name,
                        sizeBytes: runtime.sizeBytes,
                        action: runtime.canPlanDelete
                            ? RowAction("Delete") { planDelete(runtime) }
                            : nil
                    ) {
                        caption(for: runtime)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    @ViewBuilder
    private func caption(for runtime: SimRuntime) -> some View {
        if runtime.state.isBeingDeleted {
            Text("Removing…")
                .foregroundStyle(.secondary)
        } else if case let .unavailable(reason) = runtime.mutationCapability {
            Text("Actions unavailable · \(reason)")
                .foregroundStyle(.secondary)
                .lineLimit(nil)
                .fixedSize(horizontal: false, vertical: true)
        } else if runtime.isDeletable {
            Text("Build \(runtime.build)")
                .foregroundStyle(.secondary)
        } else {
            Text("Built into Xcode")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    private enum RuntimesPreviewFixtures {
        static let deletable = SimRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-18-6",
            name: "iOS 18.6",
            build: "22G86",
            sizeBytes: 7_800_000_000,
            isDeletable: true
        )

        static let bundled = SimRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.iOS-19-0",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-19-0",
            name: "iOS 19.0",
            build: "23A5260m",
            sizeBytes: 8_100_000_000,
            isDeletable: false
        )

        static let removing = SimRuntime(
            identifier: "A93FB899-77F0-41C3-9A0C-45D22BFA0A93",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            name: "iOS 26.5",
            build: "23F77",
            sizeBytes: 8_494_282_293,
            isDeletable: true,
            state: .deleting
        )

        static func model(_ runtimes: [SimRuntime]) -> AppModel {
            .previewDrillDown(.runtimes(runtimes), for: LocationCatalog.simulatorRuntimes.id)
        }
    }

    #Preview("Runtimes: populated") {
        RuntimesDetailView(
            location: LocationCatalog.simulatorRuntimes,
            model: RuntimesPreviewFixtures.model([
                RuntimesPreviewFixtures.deletable,
                RuntimesPreviewFixtures.bundled
            ])
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Runtimes: one still being removed") {
        RuntimesDetailView(
            location: LocationCatalog.simulatorRuntimes,
            model: RuntimesPreviewFixtures.model([
                RuntimesPreviewFixtures.removing,
                RuntimesPreviewFixtures.deletable
            ])
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Runtimes: empty") {
        RuntimesDetailView(
            location: LocationCatalog.simulatorRuntimes,
            model: RuntimesPreviewFixtures.model([])
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Runtimes: bundled only (non-deletable)") {
        RuntimesDetailView(
            location: LocationCatalog.simulatorRuntimes,
            model: RuntimesPreviewFixtures.model([RuntimesPreviewFixtures.bundled])
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Runtimes: still reading") {
        RuntimesDetailView(location: LocationCatalog.simulatorRuntimes, model: .previewPopulated())
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Runtimes: load error") {
        RuntimesDetailView(
            location: LocationCatalog.simulatorRuntimes,
            model: .previewDrillDownFailure(
                "simctl: permission denied",
                for: LocationCatalog.simulatorRuntimes.id
            )
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
