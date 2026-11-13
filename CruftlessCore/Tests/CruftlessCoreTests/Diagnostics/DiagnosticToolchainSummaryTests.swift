@testable import CruftlessCore
import Foundation
import Testing

@Suite("Diagnostic toolchain summary")
struct DiagnosticToolchainSummaryTests {
    private static func toolchain(_ name: String, version: String?) -> SimulatorToolchain {
        let app = URL(fileURLWithPath: "/Applications/\(name).app", isDirectory: true)
        return SimulatorToolchain(
            id: app.path,
            appURL: app,
            developerDirectory: app.appendingPathComponent("Contents/Developer", isDirectory: true),
            version: version
        )
    }

    @Test("An ambiguous resolution lists every usable candidate version")
    func ambiguousListsCandidates() {
        let candidates = [Self.toolchain("Xcode", version: "27.0"), Self.toolchain("Xcode-beta", version: "27.1beta1")]
        let summary = DiagnosticToolchainSummary(
            resolution: .unavailable(.ambiguous(candidateCount: 2)),
            candidates: candidates
        )
        #expect(summary.status == .ambiguous)
        #expect(summary.xcodeVersions == ["27.0", "27.1beta1"])
        let report = DiagnosticReportBuilder.build(snapshot(summary))
        #expect(report.contains("Xcode A: 27.0"))
        #expect(report.contains("Xcode B: 27.1beta1"))
    }

    @Test("Candidate versions are capped and sanitized by the builder")
    func candidatesAreBounded() {
        let candidates = (0 ..< 12).map { Self.toolchain("Xcode\($0)", version: "27.\($0)") }
            + [Self.toolchain("Private", version: "/Users/alice/token")]
        let summary = DiagnosticToolchainSummary(resolution: .unavailable(.candidateLimitExceeded), candidates: candidates)
        #expect(summary.xcodeVersions.count == DiagnosticReportBuilder.maximumXcodeVersions)
        let report = DiagnosticReportBuilder.build(snapshot(
            DiagnosticToolchainSummary(
                status: .ambiguous,
                source: nil,
                xcodeVersions: candidates.compactMap(\.version)
            )
        ))
        #expect(!report.contains("alice"))
        #expect(!report.contains("Xcode I:"))
    }

    @Test("A ready resolution reports only the toolchain in use")
    func readyReportsCurrent() {
        let current = Self.toolchain("Xcode", version: "27.0")
        let other = Self.toolchain("Xcode-beta", version: "27.1beta1")
        let summary = DiagnosticToolchainSummary(
            resolution: .ready(current, source: .userSelected, generation: UUID()),
            candidates: [current, other]
        )
        #expect(summary == DiagnosticToolchainSummary(status: .available, source: .userSelected, xcodeVersions: ["27.0"]))
    }

    @Test("Unchecked and timed-out resolutions map to their statuses")
    func otherStatuses() {
        #expect(DiagnosticToolchainSummary(resolution: nil, candidates: []).status == .notChecked)
        #expect(DiagnosticToolchainSummary(resolution: .unavailable(.probeFailed), candidates: []).status == .timedOut)
        #expect(DiagnosticToolchainSummary(resolution: .unavailable(.invalidSelection), candidates: []).status == .unavailable)
    }

    @Test("Only a Cruftless selection changes when the system selection is used")
    func systemSelectionChange() {
        let toolchain = Self.toolchain("Xcode", version: "27.0")
        #expect(!SimulatorToolchainResolution.ready(toolchain, source: .selected, generation: UUID()).systemSelectionWouldChange)
        #expect(!SimulatorToolchainResolution.ready(toolchain, source: .discovered, generation: UUID()).systemSelectionWouldChange)
        #expect(SimulatorToolchainResolution.ready(toolchain, source: .userSelected, generation: UUID()).systemSelectionWouldChange)
        #expect(SimulatorToolchainResolution.unavailable(.invalidSelection).systemSelectionWouldChange)
    }

    private func snapshot(_ summary: DiagnosticToolchainSummary) -> DiagnosticReportSnapshot {
        DiagnosticReportSnapshot(
            appVersion: "1.2.3", appBuild: "42", macOSVersion: "27.0", architecture: "arm64",
            toolchainResolution: summary.status, toolchainSource: summary.source,
            xcodeVersions: summary.xcodeVersions, androidSDKRootSource: nil,
            sdkIssues: [], sdkIssueCount: 0, sdkIssuesTruncated: false
        )
    }
}
