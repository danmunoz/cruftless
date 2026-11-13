import AppKit
import CruftlessCore
import SwiftUI
import UniformTypeIdentifiers

struct SupportSettingsPane: View {
    /// Seed values for previews.
    struct InitialState {
        var resolution: SimulatorToolchainResolution?
        var candidates: [SimulatorToolchain] = []
        var reportText: String?
        var notice: DiagnosticReportNotice?
        var reportIsStale = false
        var isWorkingOnToolchain = false
        var isPreparingReport = false
    }

    private static let noticeLifetime: Duration = .seconds(2)

    let resolver: SimulatorToolchainResolver
    let model: AppModel?
    @State private var resolution: SimulatorToolchainResolution?
    @State private var candidates: [SimulatorToolchain]
    @State private var selectedCandidateID: String
    @State private var isWorkingOnToolchain: Bool
    @State private var isPreparingReport: Bool
    @State private var reportText: String?
    @State private var preparedSummary: DiagnosticToolchainSummary?
    @State private var notice: DiagnosticReportNotice?
    @State private var noticeReset: Task<Void, Never>?
    private let discoversCandidatesOnAppear: Bool

    init(
        resolver: SimulatorToolchainResolver,
        discoversCandidatesOnAppear: Bool = true,
        model: AppModel? = nil,
        preview: InitialState = InitialState()
    ) {
        self.resolver = resolver
        self.discoversCandidatesOnAppear = discoversCandidatesOnAppear
        self.model = model
        _resolution = State(initialValue: preview.resolution)
        _candidates = State(initialValue: preview.candidates)
        _selectedCandidateID = State(
            initialValue: Self.preferredCandidateID(in: preview.candidates, resolution: preview.resolution)
        )
        _isWorkingOnToolchain = State(initialValue: preview.isWorkingOnToolchain)
        _isPreparingReport = State(initialValue: preview.isPreparingReport)
        _reportText = State(initialValue: preview.reportText)
        _notice = State(initialValue: preview.notice)
        let current = DiagnosticToolchainSummary(resolution: preview.resolution, candidates: preview.candidates)
        let outdated = DiagnosticToolchainSummary(status: .timedOut, source: nil, xcodeVersions: [])
        _preparedSummary = State(initialValue: preview.reportText == nil ? nil : (preview.reportIsStale ? outdated : current))
    }

    private var currentSummary: DiagnosticToolchainSummary {
        DiagnosticToolchainSummary(resolution: resolution, candidates: candidates)
    }

    private var isReportStale: Bool {
        reportText != nil && preparedSummary != currentSummary
    }

    private var isDeletionRunning: Bool {
        model?.settings.isDeletionExecuting ?? false
    }

    private var candidateSelection: Binding<String> {
        Binding(
            get: { selectedCandidateID },
            set: { newValue in
                selectedCandidateID = newValue
                Task { await applySelection(newValue) }
            }
        )
    }

    var body: some View {
        Form {
            SupportToolchainSection(
                resolution: resolution,
                candidates: candidates,
                selectedCandidateID: candidateSelection,
                isWorking: isWorkingOnToolchain,
                isDeletionRunning: isDeletionRunning,
                onRefresh: { Task { await refresh() } },
                onChoose: chooseXcode,
                onUseSystem: { Task { await useSystemSelection() } }
            )
            DiagnosticReportSection(
                reportText: reportText,
                notice: notice,
                isStale: isReportStale,
                isPreparing: isPreparingReport,
                onPrepare: { Task { await prepareReport() } },
                onCopy: copyPreviewedReport,
                onSave: savePreviewedReport
            )
        }
        .formStyle(.grouped)
        .settingsPaneSizing(estimate: 430, cap: 800)
        .task { await loadInitialState() }
        .onDisappear { noticeReset?.cancel() }
    }

    private func loadInitialState() async {
        if resolution == nil { resolution = await resolver.cachedResolution() }
        guard discoversCandidatesOnAppear, candidates.isEmpty else { return }
        candidates = await resolver.discoverUsableCandidates()
        selectedCandidateID = Self.preferredCandidateID(in: candidates, resolution: resolution)
    }

    /// The Xcode in use when it is listed, otherwise none, so every listed Xcode can be chosen.
    static func preferredCandidateID(
        in candidates: [SimulatorToolchain],
        resolution: SimulatorToolchainResolution?
    ) -> String {
        if let current = resolution?.toolchain?.id, candidates.contains(where: { $0.id == current }) {
            return current
        }
        return ""
    }

    private func refresh() async {
        guard beginToolchainWork() else { return }
        defer { isWorkingOnToolchain = false }
        resolution = await resolver.resolve(refresh: true)
        candidates = await resolver.discoverUsableCandidates(refresh: true)
        model?.refreshScan()
        selectedCandidateID = Self.preferredCandidateID(in: candidates, resolution: resolution)
    }

    private func applySelection(_ candidateID: String) async {
        guard let candidate = candidates.first(where: { $0.id == candidateID }) else { return }
        if case let .ready(current, .userSelected, _)? = resolution, current.id == candidate.id { return }
        await select(candidate.appURL)
    }

    private func select(_ appURL: URL) async {
        guard beginToolchainWork() else { return }
        defer { isWorkingOnToolchain = false }
        resolution = await resolver.select(appURL)
        model?.refreshScan()
        selectedCandidateID = Self.preferredCandidateID(in: candidates, resolution: resolution)
    }

    private func useSystemSelection() async {
        guard beginToolchainWork() else { return }
        defer { isWorkingOnToolchain = false }
        await resolver.useSystemSelection()
        resolution = await resolver.resolve(refresh: true)
        candidates = await resolver.discoverUsableCandidates(refresh: true)
        model?.refreshScan()
        selectedCandidateID = Self.preferredCandidateID(in: candidates, resolution: resolution)
    }

    /// Claims the toolchain busy state unless another toolchain action or a cleanup is running.
    private func beginToolchainWork() -> Bool {
        guard !isWorkingOnToolchain, !isDeletionRunning else { return false }
        isWorkingOnToolchain = true
        return true
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
            Task { @MainActor in await select(url) }
        }
    }

    private func copyPreviewedReport() {
        guard let reportText, !isReportStale else { return }
        NSPasteboard.general.clearContents()
        show(NSPasteboard.general.setString(reportText, forType: .string) ? .copied : .copyFailed)
    }

    private func prepareReport() async {
        guard !isPreparingReport else { return }
        isPreparingReport = true
        defer { isPreparingReport = false }
        let summary = currentSummary
        let operatingSystem = ProcessInfo.processInfo.operatingSystemVersion
        let sdkData = model?.androidSDKReportData
        reportText = DiagnosticReportBuilder.build(DiagnosticReportSnapshot(
            appVersion: CruftlessVersion.shortVersion(),
            appBuild: Bundle.main.object(forInfoDictionaryKey: CruftlessVersion.buildKey) as? String,
            macOSVersion: "\(operatingSystem.majorVersion).\(operatingSystem.minorVersion).\(operatingSystem.patchVersion)",
            architecture: Self.architecture,
            toolchainResolution: summary.status,
            toolchainSource: summary.source,
            xcodeVersions: summary.xcodeVersions,
            androidSDKRootSource: sdkData?.rootSource,
            sdkIssues: sdkData?.issues ?? [],
            sdkIssueCount: sdkData?.count ?? 0,
            sdkIssuesTruncated: sdkData?.truncated ?? false
        ))
        preparedSummary = summary
        show(.prepared)
    }

    private func savePreviewedReport() {
        guard let reportText, !isReportStale else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.plainText]
        panel.nameFieldStringValue = "Cruftless-Diagnostic-Report.txt"
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            Task { @MainActor in
                do {
                    try await DiagnosticReportExporter.save(reportText, to: url)
                    show(.saved)
                } catch {
                    show(.saveFailed)
                }
            }
        }
    }

    /// Shows a notice, and returns a transient one to the prepared state after a short delay.
    private func show(_ newNotice: DiagnosticReportNotice) {
        noticeReset?.cancel()
        notice = newNotice
        guard newNotice.isTransient else { return }
        noticeReset = Task {
            try? await Task.sleep(for: Self.noticeLifetime)
            guard !Task.isCancelled else { return }
            notice = .prepared
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
}

#if DEBUG
    private func supportPane(
        _ preview: SupportSettingsPane.InitialState,
        model: AppModel? = nil
    ) -> some View {
        SupportSettingsPane(
            resolver: SimulatorToolchainResolver(),
            discoversCandidatesOnAppear: false,
            model: model,
            preview: preview
        )
    }

    #Preview("Support: loading") {
        supportPane(.init(resolution: ToolchainPreviewFixtures.loading, isWorkingOnToolchain: true))
    }

    #Preview("Support: ready") {
        supportPane(.init(resolution: ToolchainPreviewFixtures.ready, candidates: [ToolchainPreviewFixtures.stable]))
    }

    #Preview("Support: Cruftless selection") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.userSelected,
            candidates: [ToolchainPreviewFixtures.stable, ToolchainPreviewFixtures.beta]
        ))
    }

    #Preview("Support: ambiguous") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.ambiguous,
            candidates: [ToolchainPreviewFixtures.stable, ToolchainPreviewFixtures.beta]
        ))
    }

    #Preview("Support: unavailable") {
        supportPane(.init(resolution: ToolchainPreviewFixtures.unavailable))
    }

    #Preview("Support: invalid selection") {
        supportPane(.init(resolution: .unavailable(.invalidSelection)))
    }

    #Preview("Support: cleanup running") {
        supportPane(
            .init(
                resolution: ToolchainPreviewFixtures.userSelected,
                candidates: [ToolchainPreviewFixtures.stable, ToolchainPreviewFixtures.beta]
            ),
            model: .previewDeletionRunning()
        )
    }

    #Preview("Support: report preview") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.ready,
            reportText: ToolchainPreviewFixtures.reportText,
            notice: .prepared
        ))
    }

    #Preview("Support: report copied") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.ready,
            reportText: ToolchainPreviewFixtures.reportText,
            notice: .copied
        ))
    }

    #Preview("Support: stale report") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.userSelected,
            reportText: ToolchainPreviewFixtures.reportText,
            notice: .prepared,
            reportIsStale: true
        ))
    }

    #Preview("Support: preparing report") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.ready,
            reportText: ToolchainPreviewFixtures.reportText,
            notice: .prepared,
            isPreparingReport: true
        ))
    }

    #Preview("Support: truncated report") {
        supportPane(.init(
            resolution: ToolchainPreviewFixtures.ready,
            reportText: "Cruftless Diagnostic Report\nSDK issues truncated: yes\n",
            notice: .prepared
        ))
    }

    #Preview("Support: report failure") {
        supportPane(.init(resolution: ToolchainPreviewFixtures.unavailable, notice: .saveFailed))
    }
#endif
