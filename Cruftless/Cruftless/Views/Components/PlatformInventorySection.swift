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

    private var restRows: [InventoryEntry] {
        let zeros = entries.filter { !$0.isUnavailable && $0.reclaimableBytes == 0 }
        return zeros + entries.filter(\.isUnavailable)
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
                Text("Read-only except eligible Gradle caches")
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

            if !sizedRows.isEmpty, !restRows.isEmpty {
                Hairline().padding(.vertical, 4)
            }

            ForEach(restRows) { entry in
                row(for: entry)
            }
        }
    }

    private static let androidNotice =
        "SDK, virtual devices, and Android Studio data remain read-only. "
            + "Eligible Gradle cache folders can be cleared after a one-time risk review."

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
