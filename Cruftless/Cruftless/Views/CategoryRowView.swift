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
    public let onSelect: () -> Void
    public let onAction: () -> Void
    /// Re-measures this location.
    public let onRescan: (() -> Void)?

    public init(
        entry: InventoryEntry,
        isOpening: Bool = false,
        isMeasuring: Bool = false,
        onSelect: @escaping () -> Void,
        onAction: @escaping () -> Void,
        onRescan: (() -> Void)? = nil
    ) {
        self.entry = entry
        self.isOpening = isOpening
        self.isMeasuring = isMeasuring
        self.onSelect = onSelect
        self.onAction = onAction
        self.onRescan = onRescan
    }

    private var tier: Tier {
        entry.location.tier
    }

    /// A drill-down row carries both: the row opens Detail, the capsule clears the whole location.
    private var action: RowAction? {
        let isDyldCacheCommand = entry.location.id == LocationCatalog.simulatorDyldCache.id
        // Inert while it is being re-measured, like the skeleton rows of a first scan.
        guard !entry.isUnavailable, !isMeasuring,
              !entry.location.mutationPolicy.isReadOnly || isDyldCacheCommand,
              tier != .info || isDyldCacheCommand
        else { return nil }
        return RowAction(
            DesignTokens.actionLabel(for: tier),
            isDestructive: tier.isFlagged,
            handler: onAction
        )
    }

    private var showsReadOnlyLock: Bool {
        entry.location.mutationPolicy.isReadOnly && entry.location.id != LocationCatalog.gradleCaches.id
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
            showsChevron: entry.location.hasDrillDown && !entry.isUnavailable && !isMeasuring,
            isReadOnly: showsReadOnlyLock,
            isPlaceholder: isMeasuring,
            isUnavailable: entry.isUnavailable,
            isOpening: isOpening,
            onSelect: entry.isUnavailable || isMeasuring ? nil : onSelect
        ) {
            if isMeasuring {
                Text("Measuring…")
                    .foregroundStyle(.tertiary)
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

    #Preview("Rows: every tier") {
        VStack(spacing: 2) {
            previewRow(0) // simulator devices, drill-down
            previewRow(3) // derived data, regen
            previewRow(5) // Xcode installs, reveal
            previewRow(6) // dyld cache, read-only: padlock
            previewRow(10) // archives, flagged, sub-GB size
            previewRow(12) // products/logs, sub-GB size
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

    #Preview("Rows: Android read-only and unavailable") {
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
