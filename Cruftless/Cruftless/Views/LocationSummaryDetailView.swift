import AppKit
import CruftlessCore
import SwiftUI

/// Detail for a location without a child listing: the shared header and strip over a body of facts.
struct LocationSummaryDetailView: View {
    let location: TrackedLocation
    let model: AppModel
    let backTitle: String

    @State private var pinned: InventoryEntry?

    init(location: TrackedLocation, model: AppModel, backTitle: String) {
        self.location = location
        self.model = model
        self.backTitle = backTitle
        _pinned = State(initialValue: model.inventory?.entries.first { $0.id == location.id })
    }

    private var entry: InventoryEntry? {
        model.isNavigating ? pinned : model.inventory?.entries.first { $0.id == location.id }
    }

    private var isDyldCache: Bool {
        location.id == LocationCatalog.simulatorDyldCache.id
    }

    private var detailSummary: DetailSummary? {
        guard let entry else { return nil }
        if entry.isUnavailable {
            return DetailSummary(bytes: nil, count: nil, unit: .folder)
        }
        return DetailSummary(bytes: entry.reclaimableBytes, count: entry.roots.count, unit: .folder)
    }

    /// The consequence past its first sentence, which the strip already shows.
    private var consequenceRemainder: String? {
        let remainder = location.consequence.dropFirst(location.consequenceLead.count)
            .trimmingCharacters(in: .whitespaces)
        return remainder.isEmpty ? nil : remainder
    }

    var body: some View {
        LocationDetailScaffold(location: location, model: model, backTitle: backTitle, summary: detailSummary) {
            VStack(alignment: .leading, spacing: 2) {
                if let failure = model.planFailure {
                    NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: failure)
                }

                if let entry {
                    facts(for: entry)
                } else {
                    Text("This location is no longer in the current inventory. Rescan to measure it again.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, PopoverMetrics.rowInset)
                        .padding(.top, 10)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        } footerTrailing: {
            if let entry, !entry.isUnavailable {
                footerAction(for: entry)
            }
        }
    }

    @ViewBuilder
    private func facts(for entry: InventoryEntry) -> some View {
        if let reason = entry.unavailableReason {
            NoticeStrip(symbol: "exclamationmark.triangle", tint: .orange, text: reason)
        }

        if isDyldCache {
            PopoverSectionHeader(title: "Delete from Terminal")
            factText("The cache is owned by the system. Copy the command and run it in Terminal.")
            Text(DesignTokens.dyldCacheCommand)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
                .padding(.horizontal, PopoverMetrics.rowInset)
                .padding(.top, 4)
        } else {
            PopoverSectionHeader(title: "Cleared as a whole")
            factText(consequenceRemainder.map { "Cruftless doesn't list what's inside. \($0)" }
                ?? "Cruftless doesn't list what's inside.")
        }

        if !entry.roots.isEmpty {
            PopoverSectionHeader(title: entry.roots.count == 1 ? "Location" : "Locations")
            ForEach(entry.roots, id: \.url) { root in
                rootRow(root)
            }
        }
    }

    private func factText(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, PopoverMetrics.rowInset)
            .padding(.top, 2)
    }

    private func rootRow(_ root: RootSize) -> some View {
        HStack(spacing: PopoverMetrics.rowSpacing) {
            Text(root.url.path(percentEncoded: false))
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
                .textSelection(.enabled)
                .help(root.url.path(percentEncoded: false))

            Spacer(minLength: 8)

            Text(ByteFormatter.format(root.allocatedBytes))
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, PopoverMetrics.rowInset)
        .frame(minHeight: PopoverMetrics.rowHeight)
    }

    @ViewBuilder
    private func footerAction(for entry: InventoryEntry) -> some View {
        if isDyldCache {
            Button("Copy Command") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(DesignTokens.dyldCacheCommand, forType: .string)
            }
            .buttonStyle(.glass)
            .controlSize(.large)
        } else if location.tier.isDeletable, !location.mutationPolicy.isReadOnly {
            Button("Clear") {
                Task { await model.planWholeLocation(entry) }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
            .disabled(model.isDeleting)
        }
    }
}

#if DEBUG
    #Preview("Summary detail: coding assistant") {
        LocationSummaryDetailView(location: LocationCatalog.codingAssistant, model: .previewPopulated(), backTitle: "Overview")
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Summary detail: restored cache") {
        LocationSummaryDetailView(location: LocationCatalog.previewsCache, model: .previewRestored(), backTitle: "Overview")
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Summary detail: read-only") {
        LocationSummaryDetailView(location: LocationCatalog.simulatorDyldCache, model: .previewPopulated(), backTitle: "Overview")
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Summary detail: no inventory") {
        LocationSummaryDetailView(location: LocationCatalog.previewsCache, model: AppModel(), backTitle: "Overview")
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
