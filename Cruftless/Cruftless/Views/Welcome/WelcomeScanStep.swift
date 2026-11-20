import CruftlessCore
import SwiftUI

/// The last step: the first scan as it runs, then the handoff to the menu bar.
struct WelcomeScanStep: View {
    let summary: WelcomeScanSummary
    let onOpenAccess: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 16) {
                heading
                Spacer(minLength: 0)
                MascotView(expression: mascotExpression, gaze: Self.towardResults)
                    .frame(width: 72)
                    .padding(.top, 8)
            }
            if case .failed = summary.phase {
                EmptyView()
            } else {
                total
                progressBar
                rows
                if let note = summary.accessNote, let title = summary.accessActionTitle {
                    HStack(alignment: .center, spacing: 10) {
                        WelcomeCaption(note)
                        Spacer(minLength: 0)
                        Button(title, action: onOpenAccess)
                            .controlSize(.small)
                    }
                }
            }
        }
        .animation(.snappy(duration: 0.2), value: summary)
    }

    @ViewBuilder private var heading: some View {
        switch summary.phase {
        case .starting, .scanning:
            WelcomeHeading(
                "Measuring your disk",
                subtitle: Text("Measuring never deletes anything. You can close this window, and the scan carries on in the menu bar.")
            )
        case .finished:
            WelcomeHeading(
                "Your first scan is ready",
                subtitle: Text(
                    """
                    Nothing has been deleted. Click \(WelcomeInlineGlyph.text) in the menu bar to review the results \
                    and choose what to clear.
                    """
                )
            )
        case let .failed(reason):
            WelcomeHeading(
                "The scan did not finish",
                subtitle: Text("\(reason)\n\nClick \(WelcomeInlineGlyph.text) in the menu bar to try again. Nothing has been deleted.")
            )
        }
    }

    /// Down and left of the sheep, where the total and the rows are.
    private static let towardResults = CGSize(width: -0.9, height: 0.8)

    private var mascotExpression: MascotExpression {
        switch summary.phase {
        case .starting, .scanning: .neutral
        case .finished: .happy
        case .failed: .worried
        }
    }

    private var total: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text(ByteFormatter.format(summary.cleanableBytes))
                .font(.system(size: 44, weight: .semibold))
                .monospacedDigit()
                .contentTransition(.numericText(value: Double(summary.cleanableBytes)))
            Text(summary.totalCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.top, 2)
        .accessibilityElement(children: .combine)
    }

    private var progressBar: some View {
        Capsule()
            .fill(.quaternary)
            .frame(height: 4)
            .overlay(alignment: .leading) {
                GeometryReader { proxy in
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: proxy.size.width * fraction)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(summary.progressCaption ?? (summary.isFinished ? "Scan finished" : "Scan starting"))
    }

    private var fraction: Double {
        if summary.isFinished { return 1 }
        guard summary.plannedCount > 0 else { return 0 }
        return Double(summary.completedCount) / Double(summary.plannedCount)
    }

    private var rows: some View {
        WelcomeCard {
            if summary.rows.isEmpty {
                HStack(spacing: 8) {
                    if !summary.isFinished {
                        ProgressView().controlSize(.small)
                    }
                    Text(summary.isFinished ? "No tracked location is holding recoverable space." : "Starting the scan")
                        .foregroundStyle(.secondary)
                }
                .frame(height: WelcomeScanRow.height)
                .padding(.horizontal, 14)
            }
            ForEach(summary.rows) { row in
                if row.id != summary.rows.first?.id {
                    Divider()
                }
                WelcomeScanRow(row: row)
            }
            if let remainder = summary.remainder {
                Divider()
                HStack(spacing: 10) {
                    Text("\(remainder.count) more in the menu bar")
                    Spacer(minLength: 0)
                    Text(ByteFormatter.format(remainder.bytes))
                        .monospacedDigit()
                }
                .foregroundStyle(.secondary)
                .frame(height: WelcomeScanRow.height)
                .padding(.horizontal, 14)
            }
        }
    }
}

/// One location in the first scan: its size, or why it has none yet.
struct WelcomeScanRow: View {
    static let height: CGFloat = 36

    let row: WelcomeScanSummary.Row

    var body: some View {
        HStack(spacing: 8) {
            Text(row.title)
                .lineLimit(1)
                .layoutPriority(1)
            if row.isFlagged {
                RowFlagMarker(tint: .orange)
                    .accessibilityLabel("Flagged")
            }
            Spacer(minLength: 0)
            detail
        }
        .frame(height: Self.height)
        .padding(.horizontal, 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var detail: some View {
        switch row.detail {
        case let .size(bytes):
            Text(ByteFormatter.format(bytes))
                .monospacedDigit()
        case .measuring:
            Text("Measuring…")
                .foregroundStyle(.secondary)
            ProgressView().controlSize(.small)
        case .waiting:
            Text("Waiting")
                .foregroundStyle(.tertiary)
        case let .note(text):
            Text(text)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.tail)
        }
    }
}
