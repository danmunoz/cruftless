import CruftlessCore
import SwiftUI

struct CleanupSelectionView: View {
    let model: AppModel
    @Bindable var session: CleanupSelectionSession
    var isPreviewFixture = false

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: session.location.title, backTitle: session.location.title, onBack: model.pop)
                .disabled(model.isDeleting)
            Hairline()
            SelectionControls(model: model, session: session, isPreviewFixture: isPreviewFixture)
            Hairline()

            ScrollView {
                LazyVStack(alignment: .leading, spacing: 10) {
                    SelectionNotices(model: model, session: session)
                    if session.rows.isEmpty {
                        Text(session.isRefreshing ? "Measuring items…" : "Nothing to select")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 30)
                    }
                    ForEach(session.groups) { group in
                        if group.rows.first?.groupTitle != nil {
                            SelectionGroupHeader(
                                group: group,
                                canSelect: session.isReady && !session.isRefreshing && !model.isDeleting,
                                onSelect: { model.selectEligibleCleanupRows(in: session, groupID: group.id) }
                            )
                        }
                        ForEach(group.rows) { row in
                            SelectionCheckboxRow(
                                row: row,
                                isSelected: session.selection.selectedIDs.contains(row.id),
                                canSelect: session.isReady && !session.isRefreshing,
                                isBusy: model.isDeleting,
                                onToggle: { model.toggleCleanupSelection(row, in: session) }
                            )
                        }
                    }
                }
                .padding(.horizontal, PopoverMetrics.bandInset)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            SelectionFooter(
                resolution: session.resolution,
                canReview: session.canReview && !model.isDeleting,
                onReview: { model.reviewCleanupSelection(in: session) }
            )
        }
    }
}

private struct SelectionControls: View {
    let model: AppModel
    let session: CleanupSelectionSession
    let isPreviewFixture: Bool

    var body: some View {
        HStack(spacing: 12) {
            if session.location.id != LocationCatalog.gradleCaches.id {
                Button("Select All") { model.selectEligibleCleanupRows(in: session) }
                    .disabled(!session.isReady || session.isRefreshing || model.isDeleting
                        || !session.rows.contains(where: \.selectionItem.isSelectable))
            }
            Button("Clear Selection") { model.clearCleanupSelection(in: session) }
                .disabled(session.selection.isEmpty || model.isDeleting)
            Spacer(minLength: 8)
            if session.isRefreshing {
                ProgressView().controlSize(.small)
            } else {
                Button { model.refreshSelection(session) } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Refresh this location")
                .accessibilityLabel("Refresh this location")
                .disabled(model.isDeleting || isPreviewFixture)
            }
        }
        .font(.system(size: 11))
        .buttonStyle(.plain)
        .foregroundStyle(.secondary)
        .padding(.horizontal, PopoverMetrics.bandInset)
        .padding(.vertical, 10)
    }
}

private struct SelectionNotices: View {
    let model: AppModel
    let session: CleanupSelectionSession

    private var sourcePaths: [String] {
        guard session.location.platform == .android,
              let entry = model.inventory?.entries.first(where: { $0.id == session.location.id })
        else { return [] }
        return entry.roots.map { root in
            let provenance = [root.source, root.layout.map { "\($0), volume \(root.volumeIdentifier ?? "unknown")" }]
                .compactMap(\.self)
                .joined(separator: " · ")
            return "\(provenance.isEmpty ? "Android root" : provenance) · \(root.url.path(percentEncoded: false))"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            if let notice = session.notice {
                NoticeStrip(symbol: "info.circle", tint: .orange, text: notice)
            }
            if session.location.id == LocationCatalog.gradleCaches.id {
                Text("Choose one cache entry per attempt. You’ll accept its risks before Review.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            ForEach(session.notes + sourcePaths, id: \.self) { note in
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

private struct SelectionGroupHeader: View {
    let group: CleanupSelectionGroup
    let canSelect: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text(group.title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(group.id == "runtime-removed" ? .red : .secondary)
            Spacer(minLength: 4)
            if group.rows.contains(where: \.selectionItem.isSelectable) {
                Button("Select All", action: onSelect)
                    .font(.system(size: 10))
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!canSelect)
                    .accessibilityLabel("Select all eligible items in \(group.title)")
                    .accessibilityIdentifier("cleanup.selection.group.\(group.id)")
            }
        }
        .padding(.top, 8)
        .accessibilityElement(children: .contain)
    }
}

private struct SelectionCheckboxRow: View {
    let row: CleanupSelectionRow
    let isSelected: Bool
    let canSelect: Bool
    let isBusy: Bool
    let onToggle: () -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { isSelected }, set: { _ in onToggle() })) {
            HStack(alignment: .top, spacing: 8) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(row.title)
                        .font(.system(size: 13))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    if let subtitle = row.subtitle, subtitle != row.disabledReason {
                        Text(subtitle)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let reason = row.disabledReason {
                        Text(reason)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if let action = row.actionLabel {
                        Text(action)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Text(ByteFormatter.format(row.selectionItem.reclaimableBytes))
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .fixedSize()
            }
        }
        .toggleStyle(.checkbox)
        .disabled(isBusy || (!isSelected && (!canSelect || !row.selectionItem.isSelectable)))
        .padding(.vertical, 4)
        .help(row.disabledReason ?? row.subtitle ?? row.title)
        .accessibilityLabel(
            "\(row.title), \(ByteFormatter.format(row.selectionItem.reclaimableBytes)), \(row.actionLabel ?? "Unavailable")"
        )
        .accessibilityValue(isSelected ? "Selected" : "Not selected")
        .accessibilityIdentifier("cleanup.selection.row.\(row.id)")
    }
}

private struct SelectionFooter: View {
    let resolution: CleanupSelectionResolution
    let canReview: Bool
    let onReview: () -> Void

    var body: some View {
        PopoverFooter {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(resolution.selectedCount) selected")
                        .font(.system(size: 12, weight: .medium))
                    Text("Estimated \(ByteFormatter.format(resolution.estimatedBytes))")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                .help("Allocated-size estimate. APFS clones may reduce the space actually freed.")
                Spacer(minLength: 4)
                Button("Review Selection", action: onReview)
                    .font(.system(size: 12, weight: .medium))
                    .buttonStyle(.glassProminent)
                    .controlSize(.regular)
                    .disabled(!canReview)
                    .keyboardShortcut(.defaultAction)
            }
        }
    }
}

#if DEBUG
    #Preview("Selection: empty") {
        let model = CleanupSelectionPreviewFixtures.emptyModel()
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.derivedData.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: refreshing") {
        let model = CleanupSelectionPreviewFixtures.refreshingModel()
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.derivedData.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: failed scan") {
        let model = CleanupSelectionPreviewFixtures.failedModel()
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.derivedData.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: stale IDs") {
        let model = CleanupSelectionPreviewFixtures.staleModel()
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.derivedData.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: simulator groups") {
        let model = CleanupSelectionPreviewFixtures.simulatorSelectionModel()
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.simulatorDevices.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: disabled runtimes") {
        let model = CleanupSelectionPreviewFixtures.allDisabledModel()
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.simulatorRuntimes.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Selection: selected files") {
        let model = CleanupSelectionPreviewFixtures.model(selectedIDs: [CleanupSelectionPreviewFixtures.childItems[0].id])
        CleanupSelectionView(model: model, session: model.cleanupSessions[LocationCatalog.derivedData.id]!, isPreviewFixture: true)
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
