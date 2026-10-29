#if DEBUG
    import CruftlessCore
    import SwiftUI

    enum PopoverRowPreviewFixtures {
        static let longName = "Clone 3 of iPhone 18 Pro with a very long development configuration name"

        static func rows(hovered: Bool) -> some View {
            VStack(spacing: 2) {
                PopoverRow(
                    icon: .symbol("chevron.right"), title: "Clone 3 of iPhone 18 Pro",
                    sizeBytes: 12_200_000_000,
                    action: RowAction("Delete", isDestructive: true, accessibilityLabel: "Delete Test Simulator") {}
                ) {
                    caption("839A19")
                }
                .previewHover(hovered)

                PopoverRow(
                    icon: .symbol("chevron.right"), title: longName,
                    sizeBytes: 999_900_000_000,
                    action: RowAction("Delete Test Simulator", isDestructive: true) {}
                ) {
                    caption("5CC7A5")
                }
                .previewHover(hovered)

                PopoverRow(
                    icon: .symbol("iphone"), title: longName,
                    sizeBytes: 1_200_000_000_000,
                    action: RowAction("Shut Down and Erase", isDestructive: true) {},
                    rescan: {},
                    caption: { caption("Booted") }
                )
                .previewHover(hovered)

                PopoverRow(
                    icon: .symbol("iphone"), title: longName,
                    sizeBytes: 999_900_000_000_000,
                    action: RowAction("Test-Simulator endgültig löschen", isDestructive: true) {}
                ) {
                    caption("299395")
                }
                .previewHover(hovered)
            }
            .padding(6)
            .frame(width: PopoverMetrics.width)
        }

        private static func caption(_ detail: String) -> some View {
            HStack(spacing: 4) {
                Text("iOS 27.0")
                Text(verbatim: "· \(detail)").fixedSize(horizontal: true, vertical: false)
            }
            .foregroundStyle(.secondary)
        }
    }

    #Preview("Long names: normal") {
        PopoverRowPreviewFixtures.rows(hovered: false)
    }

    #Preview("Long names: hovered") {
        PopoverRowPreviewFixtures.rows(hovered: true)
    }
#endif
