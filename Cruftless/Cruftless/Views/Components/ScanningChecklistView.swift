import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// The list as a first scan fills it in: rows that have landed, largest first, above the locations still being measured.
struct ScanningChecklistView: View {
    let progress: ScanProgress
    let onSelect: (InventoryEntry) -> Void
    let onAction: (InventoryEntry) -> Void

    var body: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                ForEach(progress.rows) { entry in
                    CategoryRowView(
                        entry: entry,
                        onSelect: { onSelect(entry) },
                        onAction: { onAction(entry) }
                    )
                }

                ForEach(progress.pending) { location in
                    PopoverRow(
                        icon: location.icon,
                        title: location.title,
                        isPlaceholder: true
                    ) {
                        Text("Measuring…")
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.top, 4)
            .padding(.bottom, 8)
            .animation(.snappy(duration: 0.2), value: progress)
        }
        .scrollBounceBehavior(.basedOnSize)
    }
}

#if DEBUG
    #Preview("Checklist: part way through") {
        ScanningChecklistView(
            progress: PreviewFixtures.partialScanProgress,
            onSelect: { _ in },
            onAction: { _ in }
        )
        .frame(width: PopoverMetrics.width, height: 300)
    }

    #Preview("Checklist: nothing measured yet") {
        var progress = ScanProgress()
        progress.plan(LocationCatalog.all)
        return ScanningChecklistView(progress: progress, onSelect: { _ in }, onAction: { _ in })
            .frame(width: PopoverMetrics.width, height: 300)
    }
#endif
