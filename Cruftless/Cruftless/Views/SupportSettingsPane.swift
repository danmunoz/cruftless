import AppKit
import CruftlessCore
import SwiftUI
import UniformTypeIdentifiers

struct SupportSettingsPane: View {
    let resolver: SimulatorToolchainResolver
    let model: AppModel?
    @State private var resolution: SimulatorToolchainResolution?
    @State private var candidates: [SimulatorToolchain] = []
    @State private var selectedCandidateID = ""
    @State private var isRefreshing = false
    @State private var reportText: String?
    @State private var reportMessage: String?
    @State private var didCopyReport = false

    init(
        resolver: SimulatorToolchainResolver,
        model: AppModel? = nil,
        initialResolution: SimulatorToolchainResolution? = nil,
        initialCandidates: [SimulatorToolchain] = [],
        initialReportText: String? = nil,
        initialReportMessage: String? = nil,
        initialIsRefreshing: Bool = false
    ) {
        self.resolver = resolver
        self.model = model
        _resolution = State(initialValue: initialResolution)
        _candidates = State(initialValue: initialCandidates)
        _selectedCandidateID = State(initialValue: initialCandidates.first?.id ?? "")
        _reportText = State(initialValue: initialReportText)
        _reportMessage = State(initialValue: initialReportMessage)
        _isRefreshing = State(initialValue: initialIsRefreshing)
    }

    var body: some View {
        Form {
            SupportToolchainSection(
                resolution: resolution,
                candidates: candidates,
                selectedCandidateID: $selectedCandidateID,
                isRefreshing: isRefreshing,
                candidateTitle: candidateTitle,
                onSelect: { Task { await selectCandidate() } },
                onRefresh: { Task { await refresh() } },
                onChoose: chooseXcode,
                onUseSystem: {
                    Task {
                        await resolver.useSystemSelection()
                        await refresh()
                    }
                }
            )
            DiagnosticReportSection(
                reportText: reportText,
                reportMessage: reportMessage,
                didCopy: didCopyReport,
                isRefreshing: isRefreshing,
                onPrepare: { Task { await prepareReport() } },
                onCopy: copyPreviewedReport,
                onSave: savePreviewedReport
            )
        }
        .formStyle(.grouped)
        .frame(width: SettingsMetrics.paneWidth, height: reportText == nil ? 430 : 620)
        .task {
            if resolution == nil { resolution = await resolver.cachedResolution() }
        }
    }

    private func refresh() async {
        isRefreshing = true
        defer { isRefreshing = false }
        resolution = await resolver.resolve(refresh: true)
        candidates = await resolver.discoverUsableCandidates(refresh: true)
        model?.refreshScan()
        if candidates.contains(where: { $0.id == selectedCandidateID }) == false {
            selectedCandidateID = candidates.first?.id ?? ""
        }
    }

    private func selectCandidate() async {
        guard let candidate = candidates.first(where: { $0.id == selectedCandidateID }) else { return }
        isRefreshing = true
        resolution = await resolver.select(candidate.appURL)
        model?.refreshScan()
        isRefreshing = false
    }

    private func chooseXcode() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.treatsFilePackagesAsDirectories = false
        panel.prompt = "Choose Xcode"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                isRefreshing = true
                resolution = await resolver.select(url)
                model?.refreshScan()
                isRefreshing = false
            }
        }
    }

    private func copyPreviewedReport() {
        guard let reportText else { return }
        NSPasteboard.general.clearContents()
        didCopyReport = NSPasteboard.general.setString(reportText, forType: .string)
        reportMessage = didCopyReport ? "Report copied." : "Could not copy the report."
    }

    private func prepareReport() async {
        isRefreshing = true
        defer { isRefreshing = false }
        let current = await resolver.cachedResolution()
        let status: DiagnosticProbeStatus
        let source: SimulatorToolchainSource?
        let versions: [String]
        switch current {
        case nil:
            status = .notChecked
            source = nil
            versions = []
        case let .some(.ready(toolchain, selectedSource, _)):
            status = .available
            source = selectedSource
            versions = toolchain.version.map { [$0] } ?? []
        case let .some(.unavailable(failure)):
            if case .ambiguous = failure {
                status = .ambiguous
            } else if case .probeFailed = failure {
                status = .timedOut
            } else {
                status = .unavailable
            }
            source = nil
            versions = []
        }
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion
        let sdkData = model?.androidSDKReportData
        reportText = DiagnosticReportBuilder.build(DiagnosticReportSnapshot(
            appVersion: CruftlessVersion.shortVersion(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: CruftlessVersion.buildKey) as? String,
            macOSVersion: "\(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)",
            architecture: Self.architecture,
            toolchainResolution: status,
            toolchainSource: source,
            xcodeVersions: versions,
            androidSDKRootSource: sdkData?.rootSource,
            sdkIssues: sdkData?.issues ?? [],
            sdkIssueCount: sdkData?.count ?? 0,
            sdkIssuesTruncated: sdkData?.truncated ?? false
        ))
        didCopyReport = false
        reportMessage = "Preview ready. Nothing has been copied or saved."
    }

    private func savePreviewedReport() {
        guard let reportText else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Cruftless-Diagnostic-Report.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await DiagnosticReportExporter.save(reportText, to: url)
                    reportMessage = "Report saved."
                } catch {
                    reportMessage = "Could not save the report to that location."
                }
            }
        }
    }

    private static var architecture: String {
        #if arch(arm64)
            "arm64"
        #elseif arch(x86_64)
            "x86_64"
        #else
            "unknown"
        #endif
    }

    private func candidateTitle(_ candidate: SimulatorToolchain) -> String {
        let name = candidate.appURL.deletingPathExtension().lastPathComponent
        guard let version = candidate.version, !version.isEmpty else { return name }
        return "\(name) · \(version)"
    }
}

private struct SupportToolchainSection: View {
    let resolution: SimulatorToolchainResolution?
    let candidates: [SimulatorToolchain]
    @Binding var selectedCandidateID: String
    let isRefreshing: Bool
    let candidateTitle: (SimulatorToolchain) -> String
    let onSelect: () -> Void
    let onRefresh: () -> Void
    let onChoose: () -> Void
    let onUseSystem: () -> Void

    var body: some View {
        Section("Simulator tools") {
            status
            if !candidates.isEmpty {
                Picker("Use Xcode", selection: $selectedCandidateID) {
                    ForEach(candidates) { candidate in
                        Text(candidateTitle(candidate)).tag(candidate.id)
                    }
                }
                Button("Use Selected Xcode", action: onSelect)
                    .disabled(selectedCandidateID.isEmpty || isRefreshing)
            }
            HStack {
                Button("Refresh Toolchain Status", action: onRefresh)
                    .disabled(isRefreshing)
                if isRefreshing { ProgressView().controlSize(.small) }
                Button("Choose Xcode…", action: onChoose)
                    .disabled(isRefreshing)
            }
            Button("Use System Selection", action: onUseSystem)
                .disabled(isRefreshing)
            Text(
                "Cruftless uses this local selection for simulator listing and actions. " +
                    "It does not change macOS’s Xcode selection. If Xcode asks to install " +
                    "components or accept its license, complete that in Xcode, then refresh."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var status: some View {
        switch resolution {
        case let .ready(toolchain, source, _):
            LabeledContent("Current") {
                Text(candidateTitle(toolchain) + " · " + sourceTitle(source))
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

    private func sourceTitle(_ source: SimulatorToolchainSource) -> String {
        switch source {
        case .selected: "System selection"
        case .discovered: "Only usable Xcode found"
        case .userSelected: "Cruftless selection"
        }
    }
}

private struct DiagnosticReportSection: View {
    let reportText: String?
    let reportMessage: String?
    let didCopy: Bool
    let isRefreshing: Bool
    let onPrepare: () -> Void
    let onCopy: () -> Void
    let onSave: () -> Void

    var body: some View {
        Section("Diagnostic report") {
            Text(
                "Prepare a local report to inspect. It includes allowlisted version and status fields only. " +
                    "Paths, usernames, host details, logs, environment values, and inventories are excluded."
            )
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button("Prepare Diagnostic Report", action: onPrepare)
                .disabled(isRefreshing)
            if isRefreshing { ProgressView().controlSize(.small) }
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
                HStack {
                    Button(didCopy ? "Copied" : "Copy Report", systemImage: didCopy ? "checkmark" : "doc.on.doc", action: onCopy)
                    Button("Save Report…", systemImage: "square.and.arrow.down", action: onSave)
                }
            }
            if let reportMessage {
                Text(reportMessage)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            Link("Open issue tracker", destination: URL(string: "https://github.com/danmunoz/cruftless/issues")!)
        }
    }
}

#if DEBUG
    #Preview("Support: loading") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: ToolchainPreviewFixtures.loading,
            initialIsRefreshing: true
        )
    }

    #Preview("Support: ready") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: ToolchainPreviewFixtures.ready,
            initialCandidates: [ToolchainPreviewFixtures.stable]
        )
    }

    #Preview("Support: ambiguous") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: ToolchainPreviewFixtures.ambiguous,
            initialCandidates: [ToolchainPreviewFixtures.stable, ToolchainPreviewFixtures.beta]
        )
    }

    #Preview("Support: unavailable") {
        SupportSettingsPane(resolver: SimulatorToolchainResolver(), initialResolution: ToolchainPreviewFixtures.unavailable)
    }

    #Preview("Support: invalid selection") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: .unavailable(.invalidSelection)
        )
    }

    #Preview("Support: report preview") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: ToolchainPreviewFixtures.ready,
            initialReportText: "Cruftless Diagnostic Report\nSchema: 1\nSimulator toolchain: available\n",
            initialReportMessage: "Preview ready. Nothing has been copied or saved."
        )
    }

    #Preview("Support: truncated report") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: ToolchainPreviewFixtures.ready,
            initialReportText: "Cruftless Diagnostic Report\nSDK issues truncated: yes\n",
            initialReportMessage: "Preview ready. Nothing has been copied or saved."
        )
    }

    #Preview("Support: report failure") {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            initialResolution: ToolchainPreviewFixtures.unavailable,
            initialReportMessage: "Could not save the report to that location."
        )
    }
#endif
