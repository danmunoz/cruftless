import AppKit
import CruftlessCore
import SwiftUI

/// Step 4, shown only when a tracked location lies in a place macOS protects.
struct WelcomeAccessStep: View {
    let accessList: AccessListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WelcomeHeading(
                "Some places need your OK",
                subtitle: Text(
                    """
                    Cruftless found things it tracks in places macOS protects. It will not look inside \
                    until you allow it, and macOS asks once per place.
                    """
                )
            )
            // Scrolls only when there are more places than fit.
            ViewThatFits(in: .vertical) {
                list
                ScrollView { list }
                    .scrollBounceBehavior(.basedOnSize)
            }
            WelcomeCaption("Skip any of them. Those items show as not measured, and you can allow them later in Settings.")
                .padding(.bottom, 4)
        }
        .onAppear { Task { await accessList.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await accessList.refresh() }
        }
    }

    private var list: some View {
        WelcomeCard {
            if !accessList.hasLoaded {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text("Checking where Cruftless needs access")
                        .foregroundStyle(.secondary)
                }
                .padding(14)
            } else if accessList.areas.isEmpty {
                Label("Nothing Cruftless tracks is in a protected place", systemImage: "checkmark.shield")
                    .foregroundStyle(.secondary)
                    .padding(14)
            } else {
                ForEach(accessList.areas) { summary in
                    if summary.id != accessList.areas.first?.id {
                        Divider()
                    }
                    WelcomeAccessAreaRow(
                        summary: summary,
                        message: accessList.messages[summary.area],
                        isRequesting: accessList.requestingArea == summary.area,
                        isAllowDisabled: accessList.isRequesting,
                        onAllow: { accessList.allow(summary.area) },
                        onOpenPrivacySettings: accessList.openPrivacySettings
                    )
                }
            }
        }
    }
}

/// One protected place: its status, the control that changes it, and what Cruftless tracks there.
struct WelcomeAccessAreaRow: View {
    let summary: AccessAreaSummary
    let message: String?
    let isRequesting: Bool
    let isAllowDisabled: Bool
    let onAllow: () -> Void
    let onOpenPrivacySettings: () -> Void

    /// Where the lines under the header start, in line with the place's name.
    private static let detailInset: CGFloat = 42

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(alignment: .center, spacing: 12) {
                WelcomeSymbolTile(symbol: symbol)
                VStack(alignment: .leading, spacing: 1) {
                    Text(summary.area.title)
                        .fontWeight(.semibold)
                    status
                }
                Spacer(minLength: 0)
                control
            }

            Group {
                if summary.status == .notAllowed {
                    WelcomeCaption("macOS will not ask again. Turn on Cruftless under Files and Folders.")
                }
                if summary.reasons.isEmpty {
                    WelcomeCaption("Nothing Cruftless tracks is here right now.")
                }
                ForEach(summary.reasons, id: \.self) { reason in
                    reasonLine(reason)
                }
                if let message {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.leading, Self.detailInset)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    private var symbol: String {
        switch summary.area {
        case .documents, .desktop, .downloads: "folder"
        case .fileProvider: "icloud"
        case .removableVolume: "externaldrive"
        case .networkVolume: "network"
        }
    }

    private var status: some View {
        HStack(spacing: 4) {
            switch summary.status {
            case .allowed:
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text("Allowed")
            case .notAsked:
                if isRequesting {
                    ProgressView().controlSize(.mini)
                    Text("Waiting for your answer")
                } else {
                    Text("Not asked yet")
                }
            case .notAllowed:
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
                Text("Not allowed")
            }
        }
        .font(.system(size: 11))
        .foregroundStyle(.secondary)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder private var control: some View {
        switch summary.status {
        case .allowed:
            EmptyView()
        case .notAsked:
            Button("Allow", action: onAllow)
                .disabled(isAllowDisabled)
                .help("macOS asks once whether Cruftless may read \(summary.area.displayName)")
                .accessibilityLabel("Allow \(summary.area.title)")
        case .notAllowed:
            Button("Open Privacy Settings", action: onOpenPrivacySettings)
        }
    }

    private func reasonLine(_ reason: AccessNeedReason) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text(reason.title)
                .layoutPriority(1)
            Text((reason.path as NSString).abbreviatingWithTildeInPath)
                .foregroundStyle(.secondary)
                .truncationMode(.head)
        }
        .font(.system(size: 11))
        .lineLimit(1)
        .help(reason.path)
        .accessibilityElement(children: .combine)
    }
}
