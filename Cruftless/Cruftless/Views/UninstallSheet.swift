import CruftlessCore
import SwiftUI

/// The review step and result of "Remove Cruftless Data".
struct UninstallSheet: View {
    let model: UninstallModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            switch model.stage {
            case .idle, .preparing:
                progress("Measuring Cruftless data…")
            case let .review(rows):
                review(rows)
            case let .refused(message):
                refused(message)
            case .removing:
                progress("Removing Cruftless data…")
            case let .finished(report):
                finished(report)
            }
        }
        .padding(20)
        .frame(width: 480)
        .interactiveDismissDisabled(model.stage == .removing || isFinished)
    }

    private var isFinished: Bool {
        if case .finished = model.stage { true } else { false }
    }

    private func progress(_ label: String) -> some View {
        HStack(spacing: 10) {
            ProgressView().controlSize(.small)
            Text(label)
        }
        .frame(maxWidth: .infinity, minHeight: 80)
    }

    private func review(_ rows: [UninstallReviewRow]) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Remove Cruftless Data").font(.headline)
            Text("These are deleted permanently:").foregroundStyle(.secondary)
            if rows.isEmpty {
                Text("No Cruftless folders are on disk.").foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Text(row.title)
                        Spacer()
                        Text(row.bytes, format: .byteCount(style: .file)).monospacedDigit().foregroundStyle(.secondary)
                    }
                    Text(verbatim: row.path).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Text(row.consequence).font(.caption)
                }
            }
            Divider()
            Text("Also undone:").foregroundStyle(.secondary)
            ForEach(UninstallModel.registrationRows, id: \.self) { Text("• \($0)") }
            Text(UninstallModel.untouchedNote).font(.caption).foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: model.cancel).keyboardShortcut(.cancelAction)
                Button("Remove Cruftless Data", role: .destructive, action: model.confirm)
            }
        }
    }

    private func refused(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Cruftless Data Was Not Removed").font(.headline)
            Text(message).fixedSize(horizontal: false, vertical: true)
            Text("Nothing was changed. To remove Cruftless by hand, quit it and delete these:")
                .foregroundStyle(.secondary)
            Text(verbatim: UninstallManualPaths.manualList)
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
            HStack {
                Spacer()
                Button("Close", action: model.cancel).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func finished(_ report: UninstallModel.UninstallReport) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(report.hasFailures ? "Some Cruftless Data Remains" : "Cruftless Data Removed").font(.headline)
            ForEach(report.registrations) { result in
                outcomeRow(result.step.title, failure: result.outcome.failureReason)
            }
            ForEach(report.files) { file in
                outcomeRow(file.title, failure: file.failure)
            }
            Text("Cruftless quits next and shows its app in Finder. Drag it to the Trash to finish.")
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Spacer()
                Button("Quit Cruftless", action: model.quit).keyboardShortcut(.defaultAction)
            }
        }
    }

    private func outcomeRow(_ title: String, failure: String?) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Image(systemName: failure == nil ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(failure == nil ? .green : .orange)
            VStack(alignment: .leading) {
                Text(title)
                if let failure { Text(failure).font(.caption).foregroundStyle(.secondary) }
            }
        }
    }
}

/// The paths a manual removal deletes, for the refusal copy.
enum UninstallManualPaths {
    static var manualList: String {
        let footprint = AppFootprint.live
        let home = footprint.home.path(percentEncoded: false)
        let paths = footprint.folders.map(\.url) + [footprint.preferencesFile]
        return paths
            .map { $0.path(percentEncoded: false).replacingOccurrences(of: home, with: "~") }
            .joined(separator: "\n")
    }
}

extension UninstallStepOutcome {
    var failureReason: String? {
        if case let .failed(reason) = self { reason } else { nil }
    }
}

#if DEBUG
    #Preview("Review") {
        UninstallSheet(model: UninstallPreviewFixtures.model(.review(UninstallPreviewFixtures.rows)))
    }

    #Preview("Review, nothing on disk") {
        UninstallSheet(model: UninstallPreviewFixtures.model(.review([])))
    }

    #Preview("Preparing") {
        UninstallSheet(model: UninstallPreviewFixtures.model(.preparing))
    }

    #Preview("Refused") {
        UninstallSheet(model: UninstallPreviewFixtures.model(.refused(UninstallPreviewFixtures.refusal)))
    }

    #Preview("Finished") {
        UninstallSheet(model: UninstallPreviewFixtures.model(.finished(UninstallPreviewFixtures.cleanReport)))
    }

    #Preview("Finished with failures") {
        UninstallSheet(model: UninstallPreviewFixtures.model(.finished(UninstallPreviewFixtures.failedReport)))
    }
#endif
