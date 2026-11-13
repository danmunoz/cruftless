import SwiftUI

enum DiagnosticReportNotice: Equatable {
    case prepared
    case copied
    case copyFailed
    case saved
    case saveFailed

    var message: String {
        switch self {
        case .prepared: "Preview ready. Nothing has been copied or saved."
        case .copied: "Report copied."
        case .copyFailed: "Could not copy the report."
        case .saved: "Report saved."
        case .saveFailed: "Could not save the report to that location."
        }
    }

    /// Success notices fade back to the prepared state.
    var isTransient: Bool {
        self == .copied || self == .saved
    }
}

struct DiagnosticReportSection: View {
    let reportText: String?
    let notice: DiagnosticReportNotice?
    let isStale: Bool
    let isPreparing: Bool
    let onPrepare: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    private var didCopy: Bool {
        notice == .copied
    }

    var body: some View {
        Section {
            HStack {
                Button("Prepare Diagnostic Report", action: onPrepare)
                    .disabled(isPreparing)
                if isPreparing { ProgressView().controlSize(.small) }
            }
            if let reportText {
                ScrollView {
                    Text(verbatim: reportText)
                        .font(.system(.caption, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                }
                .frame(height: 150)
                .background(.background.secondary, in: .rect(cornerRadius: 8))
                .opacity(isStale ? 0.6 : 1)
                HStack {
                    Button(didCopy ? "Copied" : "Copy Report", systemImage: didCopy ? "checkmark" : "doc.on.doc", action: onCopy)
                    Button("Save Report…", systemImage: "square.and.arrow.down", action: onSave)
                }
                .disabled(isStale)
            }
            if isStale {
                Label("This report is out of date. Prepare it again.", systemImage: "exclamationmark.triangle")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            } else if let notice {
                Text(notice.message)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link("Open Issue Tracker", destination: URL(string: "https://github.com/danmunoz/cruftless/issues")!)
        } header: {
            Text("Diagnostic Report")
        } footer: {
            Text(
                "Prepare a local report to inspect. It includes allowlisted version and status fields only. " +
                    "Paths, usernames, host details, logs, environment values, and inventories are excluded."
            )
        }
    }
}
