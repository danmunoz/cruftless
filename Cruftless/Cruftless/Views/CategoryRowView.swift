import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// One tracked location in the List.
public struct CategoryRowView: View {
    public let entry: InventoryEntry
    /// True while this row's drill-down is being read after a click the scan could not answer from cache.
    public var isOpening: Bool = false
    /// True while this location's size is being re-measured.
    public var isMeasuring: Bool = false
    /// Replaces the action label (for example "Copied") and keeps the hover controls shown while set.
    public var actionConfirmation: String?
    public let onSelect: () -> Void
    public let onAction: () -> Void
    /// Re-measures this location.
    public let onRescan: (() -> Void)?
    @Environment(\.openAccessSettings) private var openAccessSettings

    public init(
        entry: InventoryEntry,
        isOpening: Bool = false,
        isMeasuring: Bool = false,
        actionConfirmation: String? = nil,
        onSelect: @escaping () -> Void,
        onAction: @escaping () -> Void,
        onRescan: (() -> Void)? = nil
    ) {
        self.entry = entry
        self.isOpening = isOpening
        self.isMeasuring = isMeasuring
        self.actionConfirmation = actionConfirmation
        self.onSelect = onSelect
        self.onAction = onAction
        self.onRescan = onRescan
    }

    private var tier: Tier {
        entry.location.tier
    }

    /// A drill-down row carries both: the row opens Detail, the capsule clears the whole location. A flagged location has no capsule.
    private var action: RowAction? {
        if entry.isUnavailable, let need = entry.accessNeed {
            return accessAction(for: need)
        }
        let isDyldCacheCommand = entry.location.id == LocationCatalog.simulatorDyldCache.id
        // Inert while it is being re-measured, like the skeleton rows of a first scan.
        guard !entry.isUnavailable, !isMeasuring, tier != .irreversible, entry.reclaimableBytes > 0,
              !entry.location.mutationPolicy.isReadOnly || isDyldCacheCommand,
              tier != .info || isDyldCacheCommand,
              !tier.isDeletable || entry.canClearWholeLocation
        else { return nil }
        return RowAction(
            DesignTokens.actionLabel(for: tier),
            isDestructive: tier.isFlagged,
            confirmation: actionConfirmation,
            handler: onAction
        )
    }

    /// Opens Settings on its Access tab, where the area can be allowed.
    private func accessAction(for need: LocationAccessNeed) -> RowAction? {
        guard let openAccessSettings, !isMeasuring else { return nil }
        return RowAction(
            need.isNotAllowed ? "Review Access" : "Allow Access",
            accessibilityLabel: "Open Access settings for \(entry.location.title)",
            handler: openAccessSettings.callAsFunction
        )
    }

    public var body: some View {
        PopoverRow(
            icon: entry.location.icon,
            iconFileURL: entry.rootURLs.first,
            title: entry.location.title,
            sizeBytes: entry.isUnavailable ? nil : entry.reclaimableBytes,
            // Shows warnings only on flagged Detail rows.
            flagTint: nil,
            action: action,
            rescan: onRescan,
            // No chevron while measuring: the row is not selectable, and a first scan's pending rows do not carry one either.
            showsChevron: !entry.isUnavailable && !isMeasuring,
            isReadOnly: entry.location.isInventoryOnly,
            isPlaceholder: isMeasuring,
            isUnavailable: entry.isUnavailable,
            isOpening: isOpening,
            onSelect: entry.isUnavailable || isMeasuring ? nil : onSelect
        ) {
            if isMeasuring {
                Text("Measuring…")
                    .foregroundStyle(.tertiary)
            } else if entry.isUnavailable, let need = entry.accessNeed {
                Text(need.summary)
                    .foregroundStyle(.secondary)
                    .help(need.message)
            } else if entry.isUnavailable {
                Text("Unavailable: \(entry.unavailableReason ?? "cannot be read")")
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#if DEBUG
    private func previewRow(_ index: Int) -> some View {
        CategoryRowView(entry: PreviewFixtures.sampleEntries[index], onSelect: {}, onAction: {}, onRescan: {})
    }

    #Preview("Rows: being re-measured") {
        VStack(spacing: 2) {
            CategoryRowView(entry: PreviewFixtures.sampleEntries[3], onSelect: {}, onAction: {}, onRescan: {})
            CategoryRowView(
                entry: PreviewFixtures.sampleEntries[3],
                isMeasuring: true,
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
            CategoryRowView(
                entry: PreviewFixtures.sampleEntries[0],
                isMeasuring: true,
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
        }
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Rows: hover, focus and confirmation") {
        VStack(spacing: 2) {
            PopoverRow(
                icon: .symbol("hammer"), title: "Derived Data", sizeBytes: 4_200_000_000,
                action: RowAction("Clear") {}, rescan: {}, showsChevron: true, onSelect: {}
            )
            .previewHover(true)
            CategoryRowView(
                entry: PreviewFixtures.sampleEntries[5],
                actionConfirmation: "Copied",
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
            PopoverRow(icon: .symbol("folder"), title: "Focused row", sizeBytes: 1_200_000_000, showsChevron: true, onSelect: {})
                .previewFocus(true)
        }
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Rows: every tier") {
        VStack(spacing: 2) {
            previewRow(0) // simulator devices, drill-down
            previewRow(3) // derived data, regen
            previewRow(5) // Xcode installs, reveal
            previewRow(6) // dyld cache, read-only: padlock
            previewRow(10) // archives, flagged, no capsule, sub-GB size
            previewRow(11) // products/logs, sub-GB size
            CategoryRowView(
                entry: .sized(
                    location: LocationCatalog.ibSupport,
                    reclaimableBytes: 0,
                    staleness: StalenessInfo(lastUsedDate: nil),
                    roots: []
                ),
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
            CategoryRowView(
                entry: .unavailable(location: LocationCatalog.toolchains, reason: "permission denied"),
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
        }
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Rows: needs access, not allowed, partly measured") {
        VStack(spacing: 2) {
            ForEach(PreviewFixtures.accessNeedEntries) { entry in
                CategoryRowView(entry: entry, onSelect: {}, onAction: {}, onRescan: {})
            }
        }
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Rows: needs access, with the Access action") {
        VStack(spacing: 2) {
            ForEach(PreviewFixtures.accessNeedEntries.filter(\.isUnavailable)) { entry in
                CategoryRowView(entry: entry, onSelect: {}, onAction: {}, onRescan: {})
            }
        }
        .environment(\.openAccessSettings, OpenAccessSettingsAction {})
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Rows: Android locked, actionable and unavailable") {
        let readOnlyRegenLocation = TrackedLocation(
            id: "androidPreviewReadOnlyRegen",
            platform: .android,
            title: "Read-only cache example",
            icon: .symbol("shippingbox"),
            tier: .regen,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            mutationPolicy: .readOnly,
            resolveRoots: { [] }
        )
        VStack(spacing: 2) {
            ForEach(PreviewFixtures.androidReadOnlyEntries) { entry in
                CategoryRowView(entry: entry, onSelect: {}, onAction: {}, onRescan: {})
            }
            CategoryRowView(
                entry: .sized(
                    location: readOnlyRegenLocation,
                    reclaimableBytes: 700_000_000,
                    staleness: StalenessInfo(lastUsedDate: nil),
                    roots: []
                ),
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
            CategoryRowView(
                entry: .unavailable(location: LocationCatalog.androidSDK, reason: "SDK root cannot be read"),
                onSelect: {},
                onAction: {},
                onRescan: {}
            )
        }
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }
#endif
