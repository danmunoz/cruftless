import AppKit
import CruftlessCore
import SwiftUI

/// A grouped form listing each protected area Cruftless needs, with Allow or Open Privacy Settings per area.
public struct AccessListView<Footer: View>: View {
    let model: AccessListModel
    let footer: Footer

    /// `footer` closes the last section; the list loads on appear and again whenever the app becomes active.
    public init(model: AccessListModel, @ViewBuilder footer: () -> Footer) {
        self.model = model
        self.footer = footer()
    }

    public var body: some View {
        Form {
            if !model.hasLoaded {
                Section {
                    HStack(spacing: 8) {
                        ProgressView().controlSize(.small)
                        Text("Checking where Cruftless needs access")
                            .foregroundStyle(.secondary)
                    }
                } footer: {
                    footer
                }
            } else if model.areas.isEmpty {
                Section {
                    Label("Nothing Cruftless tracks is in a protected place", systemImage: "checkmark.shield")
                        .foregroundStyle(.secondary)
                } footer: {
                    footer
                }
            } else {
                ForEach(model.areas) { summary in
                    Section {
                        AccessAreaRows(
                            summary: summary,
                            message: model.messages[summary.area],
                            isRequesting: model.requestingArea == summary.area,
                            isAllowDisabled: model.isRequesting,
                            onAllow: { model.allow(summary.area) },
                            onOpenPrivacySettings: model.openPrivacySettings
                        )
                    } header: {
                        Text(summary.area.title)
                    } footer: {
                        if summary.id == model.areas.last?.id {
                            footer
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .onAppear { Task { await model.refresh() } }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            Task { await model.refresh() }
        }
    }
}

public extension AccessListView where Footer == EmptyView {
    init(model: AccessListModel) {
        self.init(model: model) { EmptyView() }
    }
}

/// One area's status row, its reasons, and any message about the last request.
private struct AccessAreaRows: View {
    let summary: AccessAreaSummary
    let message: String?
    let isRequesting: Bool
    let isAllowDisabled: Bool
    let onAllow: () -> Void
    let onOpenPrivacySettings: () -> Void

    var body: some View {
        LabeledContent {
            control
        } label: {
            statusLabel
            if summary.status == .notAllowed {
                Text("macOS will not ask again. Turn on Cruftless under Files and Folders.")
            }
        }

        if summary.reasons.isEmpty {
            Text("Nothing Cruftless tracks is here right now.")
                .foregroundStyle(.secondary)
        }

        ForEach(summary.reasons, id: \.self) { reason in
            AccessReasonRow(reason: reason)
        }

        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.callout)
        }
    }

    @ViewBuilder
    private var statusLabel: some View {
        switch summary.status {
        case .allowed:
            Label {
                Text("Allowed")
            } icon: {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            }
        case .notAsked:
            Label {
                Text(isRequesting ? "Waiting for your answer" : "Not asked yet")
            } icon: {
                Image(systemName: "circle.dashed").foregroundStyle(.secondary)
            }
        case .notAllowed:
            Label {
                Text("Not allowed")
            } icon: {
                Image(systemName: "xmark.circle.fill").foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var control: some View {
        switch summary.status {
        case .allowed:
            EmptyView()
        case .notAsked:
            HStack(spacing: 8) {
                if isRequesting {
                    ProgressView().controlSize(.small)
                }
                Button("Allow", action: onAllow)
                    .disabled(isAllowDisabled)
                    .help("macOS asks once whether Cruftless may read \(summary.area.displayName)")
            }
        case .notAllowed:
            Button("Open Privacy Settings", action: onOpenPrivacySettings)
        }
    }
}

/// What Cruftless tracks inside an area: its name over its tilde-abbreviated path.
private struct AccessReasonRow: View {
    let reason: AccessNeedReason

    var body: some View {
        Label {
            VStack(alignment: .leading, spacing: 1) {
                Text(reason.title)
                Text((reason.path as NSString).abbreviatingWithTildeInPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.head)
            }
        } icon: {
            Image(systemName: reason.path.hasSuffix(".app") ? "app" : "folder")
                .foregroundStyle(.secondary)
        }
        .help(reason.path)
    }
}
