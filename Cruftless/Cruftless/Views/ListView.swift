import AppKit
import CruftlessCore
import SwiftUI

/// Root screen of the popover: capacity header, the tracked locations, footer.
public struct ListView: View {
    @Bindable public var model: AppModel
    public let onOpenSettings: () -> Void

    @State private var showsUpperBoundNote = false

    public init(model: AppModel, onOpenSettings: @escaping () -> Void) {
        self.model = model
        self.onOpenSettings = onOpenSettings
    }

    public var body: some View {
        VStack(spacing: 0) {
            header
            Hairline()
            body(for: model.inventory)
            footer
        }
    }

    // MARK: - Header

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                // The running total is shown only when there is no inventory to show instead: a first ever scan, climbing from nothing.
                if let hero = heroBytes {
                    Text(ByteFormatter.format(hero))
                        .font(.system(size: 28, weight: .semibold))
                        .tracking(-0.5)
                        .monospacedDigit()
                        .contentTransition(.numericText())

                    Text("reclaimable")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)

                    if model.inventory?.sizesAreUpperBound == true {
                        Button {
                            showsUpperBoundNote.toggle()
                        } label: {
                            Image(systemName: showsUpperBoundNote ? "info.circle.fill" : "info.circle")
                                .font(.system(size: 11))
                                .foregroundStyle(showsUpperBoundNote ? AnyShapeStyle(Color.accentColor) : AnyShapeStyle(.tertiary))
                                .contentShape(.circle)
                        }
                        .buttonStyle(.plain)
                        .help("Why this is an upper bound")
                        .accessibilityLabel("Why this is an upper bound")
                    }
                } else {
                    Text("Cruftless")
                        .font(.system(size: 20, weight: .semibold))
                }

                Spacer(minLength: 8)

                refreshControl
            }
            .animation(.snappy, value: heroBytes)

            if showsUpperBoundNote, model.inventory?.sizesAreUpperBound == true {
                Text(
                    "Upper bound. Sizes are APFS-allocated and hardlink-deduplicated, but cloned "
                        + "blocks are counted once per file, so the space actually freed may be lower."
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if let inventory = model.inventory {
                CapacityBarView(
                    capacity: inventory.capacity,
                    reclaimableBytes: inventory.reclaimableBytes
                )
            }
        }
        .padding(.top, 14)
        .padding(.horizontal, PopoverMetrics.bandInset)
        .padding(.bottom, 10)
        .animation(.snappy(duration: 0.2), value: showsUpperBoundNote)
    }

    @ViewBuilder
    private var refreshControl: some View {
        if model.isScanning {
            ProgressView()
                .controlSize(.small)
                .frame(width: 26, height: 26)
                .help(scanningLabel ?? "Scanning…")
        } else {
            RefreshGlyphButton { model.refreshScan() }
        }
    }

    // MARK: - Body

    @ViewBuilder
    private func body(for inventory: Inventory?) -> some View {
        if let inventory, !inventory.entries.isEmpty {
            // A rescan keeps the rows it already has.
            entryList(inventory)
        } else if model.isScanning, model.scanProgress.hasPlan {
            scanningList
        } else if model.isScanning {
            // Before the scan has said what it will cover there is no checklist to draw: a handful of frames, usually.
            PopoverPlaceholder(
                symbol: "magnifyingglass",
                title: "Scanning…",
                message: nil
            )
        } else if let failure = model.scanFailure, inventory == nil {
            PopoverPlaceholder(
                symbol: "exclamationmark.triangle",
                title: "Scan failed",
                message: failure
            ) {
                Button("Try Again") { model.refreshScan() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        } else if inventory == nil {
            PopoverPlaceholder(
                symbol: "internaldrive",
                title: "Nothing scanned yet",
                message: "Nothing is deleted without your review."
            ) {
                Button("Scan") { model.refreshScan() }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
            }
        } else {
            PopoverPlaceholder(
                symbol: "checkmark.circle",
                title: "Nothing to reclaim",
                message: "No tracked location is holding recoverable space."
            )
        }
    }

    /// The number the hero shows: the finished total when there is one, and the running total of a first ever scan otherwise.
    private var heroBytes: Int64? {
        if let inventory = model.inventory {
            return inventory.reclaimableBytes
        }
        guard model.isScanning, model.scanProgress.hasPlan, !model.scanProgress.rows.isEmpty else {
            return nil
        }
        return model.scanProgress.reclaimableBytes
    }

    /// "Scanning 6 of 13…" while a full scan the user asked for is running, nil otherwise.
    private var scanningLabel: String? {
        let progress = model.scanProgress
        guard model.isScanning, progress.hasPlan else { return nil }
        return "Scanning \(progress.completedCount) of \(progress.plannedCount)…"
    }

    /// The locations being measured at this instant.
    private var measuringIds: Set<String> {
        model.isScanning ? model.scanProgress.measuring : []
    }

    private var scanningList: some View {
        ScanningChecklistView(
            progress: model.scanProgress,
            onSelect: select,
            onAction: { performAction(for: $0) }
        )
    }

    private func entryList(_ inventory: Inventory) -> some View {
        // Once, not once per row: every row asks the same question of it, and the animation below is keyed on the same value.
        let measuring = measuringIds
        return ScrollView {
            LazyVStack(spacing: 2) {

                ForEach(model.preferenceIssues, id: \.self) { issue in
                    NoticeStrip(symbol: "gearshape.fill", tint: .orange, text: issue.message)
                }

                if let failure = model.scanFailure {
                    NoticeStrip(symbol: "exclamationmark.circle.fill", tint: .red, text: failure)
                }

                if let planFailure = model.planFailure {
                    NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: planFailure)
                }

                // A rescan skeletons only the row it is measuring right now.
                ForEach(inventory.entries) { entry in
                    CategoryRowView(
                        entry: entry,
                        isOpening: model.preparingLocationId == entry.location.id,
                        isMeasuring: measuring.contains(entry.location.id),
                        onSelect: { select(entry) },
                        onAction: { performAction(for: entry) }
                    )
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .animation(.snappy(duration: 0.2), value: measuring)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var footer: some View {
        ListFooter(
            scanningLabel: scanningLabel,
            scannedAt: model.inventory?.scannedAt,
            isAutomaticScanPaused: model.isAutomaticScanPaused,
            runningAppsLabel: model.runningAppsFooterLabel,
            runningAppsWarning: model.runningAppsWarning,
            onOpenSettings: onOpenSettings
        )
    }

    // MARK: - Actions

    private func select(_ entry: InventoryEntry) {
        guard !entry.isUnavailable else { return }
        if entry.location.hasDrillDown {
            model.openDetail(for: entry.location)
        } else {
            performAction(for: entry)
        }
    }

    private func performAction(for entry: InventoryEntry) {
        switch entry.location.tier {
        case .reveal:
            if let appURL = entry.rootURLs.first {
                NSWorkspace.shared.activateFileViewerSelecting([appURL])
            }
        case .info:
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(DesignTokens.dyldCacheCommand, forType: .string)
        case .irreversible:
            // Never actioned in bulk from the list.
            if entry.location.hasDrillDown {
                model.openDetail(for: entry.location)
            } else {
                model.reportPlanFailure(
                    "\(entry.location.title) holds irreversible items and can only be cleared one at a time."
                )
            }
        case .regen, .judgment:
            guard !model.isInventoryRestored else {
                model.refuseActionOnRestoredInventory()
                return
            }
            Task { await planWholeLocation(entry) }
        }
    }

    private func planWholeLocation(_ entry: InventoryEntry) async {
        let location = entry.location
        let children: [ChildEntry]
        if entry.roots.contains(where: { location.isCustomRoot($0.url) }) {
            // The scan's own listing when it has one; a walk only when it does not, which is the same cold path `openDetail` takes.
            if let listed = model.drillDowns[location.id]?.children {
                children = listed
            } else {
                children = await model.scanEngine.children(of: location.id)
            }
        } else {
            children = []
        }
        model.plan { context in
            try DeletionPlanner.wholeLocation(entry, context: context.withChildren { _ in children })
        }
    }
}

/// The header's rescan control at rest: the glyph alone, tinting to full contrast under the pointer.
struct RefreshGlyphButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.trianglehead.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
        .help("Rescan tracked locations")
        .accessibilityLabel("Rescan")
    }
}

/// Quiet footer control that still reads as clickable, with its own hover and pressed states.
struct FooterButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(.quaternary.opacity(isHovered ? 1 : 0))
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Inline, non-blocking notice.
struct NoticeStrip: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PopoverMetrics.rowInset)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: PopoverMetrics.rowCornerRadius, style: .continuous)
                .fill(tint.opacity(0.1))
        }
        .padding(.bottom, 4)
    }
}
