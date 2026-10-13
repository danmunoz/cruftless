import AppKit
import CruftlessCore
import SwiftUI

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

    var body: some View {
        VStack(spacing: 0) {
            LocationDetailScaffold(location: location, model: model, backTitle: backTitle) {
                VStack(alignment: .leading, spacing: 12) {
                    if let entry {
                        Text(entry.isUnavailable ? "—" : ByteFormatter.format(entry.reclaimableBytes))
                            .font(.system(size: 22, weight: .semibold))
                            .monospacedDigit()

                        Text(DesignTokens.tierWord(for: location.tier, locationId: location.id))
                            .font(.callout)
                            .foregroundStyle(DesignTokens.tierColor(for: location.tier))

                        Text(location.consequence)
                            .font(.callout)
                            .foregroundStyle(.secondary)

                        ForEach(entry.roots, id: \.url) { root in
                            Text(root.url.path(percentEncoded: false))
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }

                        if let reason = entry.unavailableReason {
                            NoticeStrip(symbol: "exclamationmark.triangle", tint: .orange, text: reason)
                        }
                    } else {
                        Text("This location is no longer in the current inventory. Rescan to measure it again.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }

                    if let failure = model.planFailure {
                        NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: failure)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(PopoverMetrics.bandInset)
            }

            if let entry, !entry.isUnavailable {
                PopoverFooter {
                    HStack {
                        Spacer()
                        if location.id == LocationCatalog.simulatorDyldCache.id {
                            Button("Copy Command") {
                                NSPasteboard.general.clearContents()
                                NSPasteboard.general.setString(DesignTokens.dyldCacheCommand, forType: .string)
                            }
                            .buttonStyle(.glass)
                        } else if location.tier.isDeletable, !location.mutationPolicy.isReadOnly {
                            Button("Clear") {
                                Task { await model.planWholeLocation(entry) }
                            }
                            .buttonStyle(.glass)
                            .disabled(model.isDeleting)
                        }
                    }
                }
            }
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
