import CruftlessCore
import SwiftUI

struct SupportToolchainSection: View {
    let resolution: SimulatorToolchainResolution?
    let candidates: [SimulatorToolchain]
    let selectedCandidateID: Binding<String>
    let isWorking: Bool
    let isDeletionRunning: Bool
    let onRefresh: () -> Void
    let onChoose: () -> Void
    let onUseSystem: () -> Void

    private var isLocked: Bool {
        isWorking || isDeletionRunning
    }

    private var canUseSystemSelection: Bool {
        resolution?.systemSelectionWouldChange ?? true
    }

    var body: some View {
        Section {
            status
            if !candidates.isEmpty {
                Picker("Use Xcode", selection: selectedCandidateID) {
                    if selectedCandidateID.wrappedValue.isEmpty { Text("Choose an Xcode").tag("") }
                    ForEach(candidates) { candidate in
                        Text(Self.title(for: candidate)).tag(candidate.id)
                    }
                }
                .disabled(isLocked)
            }
            HStack {
                Button("Refresh Toolchain Status", action: onRefresh)
                Button("Choose Xcode…", action: onChoose)
                if isWorking { ProgressView().controlSize(.small) }
            }
            .disabled(isLocked)
            Button("Use System Selection", action: onUseSystem)
                .disabled(isLocked || !canUseSystemSelection)
            if isDeletionRunning {
                Text("Unavailable while a cleanup is running.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        } header: {
            Text("Simulator Tools")
        } footer: {
            Text(
                "Cruftless uses this local selection for simulator listing and actions. " +
                    "It does not change macOS’s Xcode selection. If Xcode asks to install " +
                    "components or accept its license, complete that in Xcode, then refresh."
            )
        }
    }

    @ViewBuilder
    private var status: some View {
        switch resolution {
        case let .ready(toolchain, source, _):
            LabeledContent("Current") {
                Text(Self.title(for: toolchain) + " · " + Self.sourceTitle(source))
                    .foregroundStyle(.secondary)
            }
        case let .unavailable(failure):
            Label(failure.localizedDescription, systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        case nil:
            Label("Not checked. Refresh to inspect simulator tools.", systemImage: "questionmark.circle")
                .foregroundStyle(.secondary)
        }
    }

    static func title(for toolchain: SimulatorToolchain) -> String {
        let name = toolchain.appURL.deletingPathExtension().lastPathComponent
        guard let version = toolchain.version, !version.isEmpty else { return name }
        return "\(name) · \(version)"
    }

    private static func sourceTitle(_ source: SimulatorToolchainSource) -> String {
        switch source {
        case .selected: "System selection"
        case .discovered: "Only usable Xcode found"
        case .userSelected: "Cruftless selection"
        }
    }
}
