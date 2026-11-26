import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

struct PlatformInventorySection: View {
    let platform: DevelopmentPlatform
    let entries: [InventoryEntry]
    let measuring: Set<String>
    let preparingLocationId: String?
    var planningLocationId: String?
    var copiedLocationId: String?
    let showsTopSeparator: Bool
    let onSelect: (InventoryEntry) -> Void
    let onAction: (InventoryEntry) -> Void
    let onRescan: (String) -> Void

    private var sizedRows: [InventoryEntry] {
        entries.filter { !$0.isUnavailable && $0.reclaimableBytes > 0 }
    }

    private var unavailableRows: [InventoryEntry] {
        entries.filter(\.isUnavailable)
    }

    private var emptyRows: [InventoryEntry] {
        entries.filter { !$0.isUnavailable && $0.reclaimableBytes == 0 }
    }

    @State private var showsEmptyRows: Bool

    init(
        platform: DevelopmentPlatform,
        entries: [InventoryEntry],
        measuring: Set<String>,
        preparingLocationId: String?,
        planningLocationId: String? = nil,
        copiedLocationId: String? = nil,
        showsTopSeparator: Bool,
        showsEmptyRows: Bool = false,
        onSelect: @escaping (InventoryEntry) -> Void,
        onAction: @escaping (InventoryEntry) -> Void,
        onRescan: @escaping (String) -> Void
    ) {
        self.platform = platform
        self.entries = entries
        self.measuring = measuring
        self.preparingLocationId = preparingLocationId
        self.planningLocationId = planningLocationId
        self.copiedLocationId = copiedLocationId
        self.showsTopSeparator = showsTopSeparator
        _showsEmptyRows = State(initialValue: showsEmptyRows)
        self.onSelect = onSelect
        self.onAction = onAction
        self.onRescan = onRescan
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            if showsTopSeparator {
                Hairline().padding(.vertical, 4)
            }

            Text(platform.sectionTitle)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .padding(.horizontal, PopoverMetrics.rowInset)
                .padding(.top, 6)
                .padding(.bottom, platform == .android ? 0 : 2)

            if platform == .android {
                Text("Read-only except Gradle caches and devices")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .padding(.horizontal, PopoverMetrics.rowInset)
                    .padding(.bottom, 2)
                    .help(Self.androidNotice)
                    .accessibilityLabel(Self.androidNotice)
            }

            ForEach(sizedRows) { entry in
                row(for: entry)
            }

            if !sizedRows.isEmpty, !(unavailableRows.isEmpty && emptyRows.isEmpty) {
                Hairline().padding(.vertical, 4)
            }

            ForEach(unavailableRows) { entry in
                row(for: entry)
            }

            if !emptyRows.isEmpty {
                emptyHeader

                if showsEmptyRows {
                    ForEach(emptyRows) { entry in
                        row(for: entry)
                    }
                }
            }
        }
    }

    /// Toggles the rows measured at 0 B, which start collapsed.
    private var emptyHeader: some View {
        Button {
            withAnimation(.snappy(duration: 0.2)) { showsEmptyRows.toggle() }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 9, weight: .semibold))
                    .rotationEffect(.degrees(showsEmptyRows ? 90 : 0))
                Text("Empty")
                    .font(.system(size: 11, weight: .semibold))
                Text("\(emptyRows.count)")
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
                Spacer(minLength: 0)
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, PopoverMetrics.rowInset)
            .padding(.vertical, 6)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Empty locations, \(emptyRows.count)")
        .accessibilityValue(showsEmptyRows ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides locations that hold nothing to clean.")
        .accessibilityIdentifier("inventory.empty-toggle.\(platform.rawValue)")
    }

    private static let androidNotice =
        "Android Studio data remains read-only. "
            + "Eligible Gradle cache folders can be cleared after a one-time risk review. "
            + "Stopped virtual devices and unused SDK packages can be removed one at a time after review."

    private func row(for entry: InventoryEntry) -> some View {
        CategoryRowView(
            entry: entry,
            isOpening: preparingLocationId == entry.location.id || planningLocationId == entry.location.id,
            isMeasuring: measuring.contains(entry.location.id),
            actionConfirmation: copiedLocationId == entry.location.id ? "Copied" : nil,
            onSelect: { onSelect(entry) },
            onAction: { onAction(entry) },
            onRescan: { onRescan(entry.location.id) }
        )
    }
}

private extension DevelopmentPlatform {
    var sectionTitle: String {
        switch self {
        case .apple: "Apple development"
        case .android: "Android development"
        }
    }
}

#if DEBUG
    #Preview("Platform section: Apple") {
        PlatformInventorySection(
            platform: .apple,
            entries: PreviewFixtures.sampleEntries.filter { $0.location.platform == .apple },
            measuring: [],
            preparingLocationId: nil,
            showsTopSeparator: false,
            onSelect: { _ in },
            onAction: { _ in },
            onRescan: { _ in }
        )
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Platform section: Apple, empty rows expanded") {
        PlatformInventorySection(
            platform: .apple,
            entries: PreviewFixtures.sampleEntries.filter { $0.location.platform == .apple },
            measuring: [],
            preparingLocationId: nil,
            showsTopSeparator: false,
            showsEmptyRows: true,
            onSelect: { _ in },
            onAction: { _ in },
            onRescan: { _ in }
        )
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Platform section: Android") {
        PlatformInventorySection(
            platform: .android,
            entries: PreviewFixtures.androidReadOnlyEntries,
            measuring: [],
            preparingLocationId: nil,
            showsTopSeparator: true,
            onSelect: { _ in },
            onAction: { _ in },
            onRescan: { _ in }
        )
        .frame(width: PopoverMetrics.width)
    }
#endif
