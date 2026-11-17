import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// A Detail row for a root the access gate kept the scan out of: named, read-only, never sized.
struct BlockedAccessRow: View {
    let blocked: BlockedAccess
    @Environment(\.openAccessSettings) private var openAccessSettings

    private var action: RowAction? {
        guard let openAccessSettings else { return nil }
        return RowAction(
            blocked.state == .notAllowed ? "Review Access" : "Allow Access",
            accessibilityLabel: "Open Access settings for \(blocked.reason)",
            handler: openAccessSettings.callAsFunction
        )
    }

    var body: some View {
        PopoverRow(
            icon: nil,
            title: blocked.reason,
            sizeBytes: nil,
            sizePlaceholder: "Not measured",
            action: action,
            isReadOnly: true,
            isUnavailable: true
        ) {
            Text(blocked.summary)
                .foregroundStyle(.secondary)
        }
        .help(blocked.path)
    }
}

#if DEBUG
    #Preview("Blocked rows: not asked and not allowed") {
        let blocked = PreviewFixtures.accessNeedEntries.compactMap(\.accessNeed).flatMap(\.blocked)
        VStack(spacing: 2) {
            ForEach(blocked, id: \.path) { BlockedAccessRow(blocked: $0) }
        }
        .environment(\.openAccessSettings, OpenAccessSettingsAction {})
        .padding(8)
        .frame(width: PopoverMetrics.width)
    }
#endif
