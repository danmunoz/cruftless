import CruftlessCore
import SwiftUI

/// Drill-down for CoreSimulator devices.
public struct SimulatorsDetailView: View {
    public let location: TrackedLocation
    @Bindable public var model: AppModel
    public let backTitle: String

    @State private var expanded: Set<String> = []
    @State private var bloat: [String: [BloatSubPath]] = [:]

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

    private var devices: [SimDevice] {
        contents?.devices?.devices ?? []
    }

    /// A device directory is named for its UDID, so the scan's per-child breakdown is already a per-device size table.
    private var sizes: [String: Int64] {
        contents?.devices?.sizes ?? [:]
    }

    #if DEBUG
        /// Preview-only seam for this screen's *own* state: which devices are expanded and what their known-bloat listing holds.
        init(
            location: TrackedLocation,
            model: AppModel,
            backTitle: String = "Overview",
            previewBloat: [String: [BloatSubPath]] = [:],
            previewExpanded: Set<String> = []
        ) {
            self.location = location
            self.model = model
            self.backTitle = backTitle
            _bloat = State(initialValue: previewBloat)
            _expanded = State(initialValue: previewExpanded)
            _pinned = State(initialValue: model.drillDowns[location.id])
        }
    #endif

    private var unavailable: [SimDevice] {
        devices.filter(\.isUnavailable)
    }

    private var available: [SimDevice] {
        devices.filter { !$0.isUnavailable }
    }

    private var runtimeSections: [RuntimeSection] {
        Dictionary(grouping: available, by: \.runtime)
            .map { runtimeId, devices in
                RuntimeSection(runtimeId: runtimeId, devices: devices, total: total(of: devices))
            }
            .sorted { $0.total > $1.total }
    }

    public var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: location.title, backTitle: backTitle, onBack: model.pop)
            Hairline()

            LoadStateView(
                isLoading: contents == nil,
                loadingTitle: "Reading simulators…",
                error: contents?.failureReason,
                errorTitle: "Couldn't read simulators",
                isEmpty: devices.isEmpty,
                emptySymbol: "iphone.slash",
                emptyTitle: "No simulators",
                emptyMessage: "CoreSimulator has no devices on this Mac.",
                retry: { model.reloadDrillDown(for: location) },
                content: { content }
            )

            if let planFailure = model.planFailure {
                NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: planFailure)
                    .padding(.horizontal, 6)
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                if !unavailable.isEmpty {
                    runtimeRemovedHeader
                    ForEach(unavailable) { unavailableRow($0) }
                }

                ForEach(runtimeSections, id: \.runtimeId) { section in
                    PopoverSectionHeader(
                        title: Naming.runtime(identifier: section.runtimeId),
                        subtitle: Text(
                            "^[\(section.devices.count) device](inflect: true) · \(ByteFormatter.format(section.total))"
                        )
                    )
                    ForEach(section.devices) { device in
                        deviceRow(device)
                        if expanded.contains(device.udid) {
                            bloatGroup(for: device)
                        }
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var runtimeRemovedHeader: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Runtime removed")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DesignTokens.tierColor(for: .irreversible))

            Spacer(minLength: 8)

            Text(ByteFormatter.format(total(of: unavailable)))
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
                .monospacedDigit()
        }
        .padding(.horizontal, PopoverMetrics.rowInset)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }

    private func total(of group: [SimDevice]) -> Int64 {
        group.reduce(0) { $0 + (sizes[$1.udid] ?? 0) }
    }

    private func sizeBytes(for device: SimDevice) -> Int64? {
        sizes[device.udid]
    }

    private func unavailableRow(_ device: SimDevice) -> some View {
        PopoverRow(
            icon: .symbol("exclamationmark.triangle"),
            title: device.name,
            sizeBytes: sizeBytes(for: device),
            action: RowAction(DesignTokens.actionLabel(for: .irreversible), isDestructive: true) { plan(.delete, for: device) }
        ) {
            HStack(spacing: 4) {
                Text(Naming.runtime(identifier: device.runtime))
                    .foregroundStyle(.secondary)
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)
                Text("Can't boot")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func deviceRow(_ device: SimDevice) -> some View {
        PopoverRow(
            icon: .symbol(expanded.contains(device.udid) ? "chevron.down" : "chevron.right"),
            title: device.name,
            sizeBytes: sizeBytes(for: device),
            action: eraseAction(for: device),
            onSelect: { toggle(device) },
            caption: { deviceCaption(device) }
        )
    }

    /// Booted shows a green dot.
    @ViewBuilder
    private func deviceCaption(_ device: SimDevice) -> some View {
        if device.state.isBooted {
            HStack(spacing: 4) {
                Circle().fill(.green).frame(width: 6, height: 6)
                Text("Booted").foregroundStyle(.secondary)
            }
        }
    }

    private func eraseAction(for device: SimDevice) -> RowAction {
        RowAction(device.state.isBooted ? "Shut Down and Erase" : "Erase") {
            plan(.erase, for: device)
        }
    }

    @ViewBuilder
    private func bloatGroup(for device: SimDevice) -> some View {
        let paths = bloat[device.udid] ?? []
        let total = paths.reduce(0) { $0 + $1.allocatedBytes }

        VStack(alignment: .leading, spacing: 6) {
            if paths.isEmpty {
                Text("Nothing reclaimable inside this device.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                Text("Reclaimable inside this device · \(ByteFormatter.format(total))")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)

                ForEach(paths) { path in
                    HStack {
                        Text(path.title)
                            .font(.system(size: 12))
                        Spacer(minLength: 8)
                        Text(ByteFormatter.format(path.allocatedBytes))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                }

                HStack {
                    Spacer()
                    Button("Clear") { plan(.bloat, for: device) }
                        .buttonStyle(.glass)
                        .controlSize(.small)
                        .disabled(!device.state.isShutdown)
                        .help(device.state.isShutdown ? "" : "Shut the simulator down first.")
                }
            }
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 12))
        .padding(.leading, 30)
        .padding(.trailing, 6)
        .padding(.vertical, 2)
        .task(id: device.udid) {
            await loadBloatIfNeeded(for: device)
        }
    }
}

private struct RuntimeSection {
    let runtimeId: String
    let devices: [SimDevice]
    let total: Int64
}

private enum SimulatorDeviceAction { case erase, delete, bloat }

// MARK: - Behaviour

private extension SimulatorsDetailView {
    func toggle(_ device: SimDevice) {
        if expanded.contains(device.udid) {
            expanded.remove(device.udid)
        } else {
            expanded.insert(device.udid)
        }
    }

    /// Loads `knownBloat` for one device into the cache, unless it is already cached.
    func loadBloatIfNeeded(for device: SimDevice) async {
        guard bloat[device.udid] == nil else { return }
        let service = model.simulatorService
        let result = await Self.knownBloat(service: service, device: device)
        guard !Task.isCancelled else { return }
        bloat[device.udid] = result
    }

    nonisolated static func knownBloat(service: SimulatorService, device: SimDevice) async -> [BloatSubPath] {
        service.knownBloat(for: device)
    }

    /// Planning refusals are shown, not swallowed.
    func plan(_ action: SimulatorDeviceAction, for device: SimDevice) {
        let size = sizes[device.udid] ?? 0
        model.plan { context in
            let plan: DeletionPlan = switch action {
            case .erase: try DeletionPlanner.simulatorErase(for: device, size: size, context: context)
            case .delete: try DeletionPlanner.simulatorDelete(for: device, size: size, context: context)
            case .bloat: try DeletionPlanner.simulatorBloat(for: device, context: context)
            }
            guard !plan.isEmpty else {
                throw DeletionPlanningError.nothingToPlan(title: device.name)
            }
            return plan
        }
    }

}
