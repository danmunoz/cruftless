import AppKit
import CruftlessCore
import SwiftUI

/// The List's footer: what the numbers on screen are worth, and the two always-available commands.
struct ListFooter: View {
    /// "Scanning 6 of 13…" while a scan the user asked for is running.
    let scanningLabel: String?
    let scannedAt: Date?
    let isAutomaticScanPaused: Bool
    /// "Xcode running": the condensed form.
    var runningAppsLabel: String?
    /// The full sentence behind that label, for `.help` and VoiceOver.
    var runningAppsWarning: String?
    let onOpenSettings: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Hairline()

            HStack(spacing: 0) {
                status
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)

                runningAppsSegment

                Spacer(minLength: 8)

                HStack(spacing: 14) {
                    FooterButton("Settings", action: onOpenSettings)
                        .keyboardShortcut(",", modifiers: .command)

                    FooterButton("Quit") {
                        NSApplication.shared.terminate(nil)
                    }
                    .keyboardShortcut("q", modifiers: .command)
                }
                .fixedSize()
            }
            .padding(.horizontal, 12)
            .frame(height: PopoverMetrics.footerHeight)
        }
    }

    private var pausedSuffix: String {
        isAutomaticScanPaused ? " · Paused in Low Power Mode" : ""
    }

    @ViewBuilder
    private var runningAppsSegment: some View {
        if let runningAppsLabel {
            HStack(spacing: 5) {
                Text(verbatim: "·")
                    .foregroundStyle(.tertiary)

                Circle()
                    .fill(DesignTokens.tierColor(for: .judgment))
                    .frame(width: 6, height: 6)

                Text(runningAppsLabel)
                    .foregroundStyle(.secondary)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .fixedSize()
            .padding(.leading, 5)
            .help(runningAppsWarning ?? runningAppsLabel)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(runningAppsWarning ?? runningAppsLabel)
        }
    }

    @ViewBuilder
    private var status: some View {
        if let scanningLabel {
            Text(scanningLabel)
        } else if let scannedAt {
            // A relative format, so the line keeps itself current while the popover stays open.
            Text("Scanned \(scannedAt, format: .relative(presentation: .named))\(pausedSuffix)")
        } else if isAutomaticScanPaused {
            // Without this the paused state is indistinguishable from a scan that silently failed to start.
            Text("Paused in Low Power Mode")
        } else {
            Text("Not scanned yet")
        }
    }
}

#if DEBUG
    #Preview("Footer: every state") {
        VStack(spacing: 0) {
            ListFooter(
                scanningLabel: "Scanning 6 of 13…",
                scannedAt: .now.addingTimeInterval(-7200),
                isAutomaticScanPaused: false,
                onOpenSettings: {}
            )
            ListFooter(
                scanningLabel: nil,
                scannedAt: .now.addingTimeInterval(-7200),
                isAutomaticScanPaused: false,
                onOpenSettings: {}
            )
            ListFooter(
                scanningLabel: nil,
                scannedAt: .now.addingTimeInterval(-7200),
                isAutomaticScanPaused: true,
                onOpenSettings: {}
            )
            ListFooter(
                scanningLabel: nil,
                scannedAt: .now.addingTimeInterval(-7200),
                isAutomaticScanPaused: false,
                runningAppsLabel: RunningDeveloperApps.both.footerLabel,
                runningAppsWarning: RunningDeveloperApps.both.warning,
                onOpenSettings: {}
            )
            ListFooter(
                scanningLabel: nil,
                scannedAt: nil,
                isAutomaticScanPaused: false,
                onOpenSettings: {}
            )
        }
        .frame(width: PopoverMetrics.width)
    }
#endif
