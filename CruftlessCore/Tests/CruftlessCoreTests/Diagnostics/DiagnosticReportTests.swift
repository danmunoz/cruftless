import CruftlessCore
import Foundation
import Testing

@Suite("Diagnostic report privacy")
struct DiagnosticReportTests {
    @Test("Only allowlisted metadata is exported")
    func privateInputsAreOmitted() {
        let report = DiagnosticReportBuilder.build(DiagnosticReportSnapshot(
            appVersion: "daniel-secret-token",
            appBuild: "alice-token",
            macOSVersion: "14.4\nHOST-SECRET",
            architecture: "daniel-host",
            toolchainResolution: .available,
            toolchainSource: .selected,
            xcodeVersions: ["26.0", "/Users/alice/Secret.app/host-token"],
            androidSDKRootSource: "/Users/alice/Custom SDK",
            sdkIssues: [
                issue("system-images;android-36;private_project;alice"),
                issue("extras;private-company;secret-package"),
                issue("platforms;android-36")
            ],
            sdkIssueCount: 3,
            sdkIssuesTruncated: false
        ))

        #expect(!report.contains("alice"))
        #expect(!report.contains("daniel"))
        #expect(!report.contains("secret"))
        #expect(!report.contains("private_project"))
        #expect(!report.contains("/Users"))
        #expect(report.contains("identity=platforms;android-36"))
        #expect(report.contains("identity=omitted"))
        #expect(report.contains("Architecture: unknown"))
    }

    @Test("Output is deterministic and bounded")
    func outputIsDeterministicAndBounded() {
        let item = issue("platforms;android-36")
        let snapshot = DiagnosticReportSnapshot(
            appVersion: "1.2.3",
            appBuild: "42",
            macOSVersion: "27.0",
            architecture: "arm64",
            toolchainResolution: .notChecked,
            toolchainSource: nil,
            xcodeVersions: [],
            androidSDKRootSource: "ANDROID_HOME",
            sdkIssues: Array(repeating: item, count: DiagnosticReportBuilder.maximumSDKIssues + 20),
            sdkIssueCount: 500,
            sdkIssuesTruncated: true
        )
        let first = DiagnosticReportBuilder.build(snapshot)
        let second = DiagnosticReportBuilder.build(snapshot)

        #expect(first == second)
        #expect(first.utf8.count <= DiagnosticReportBuilder.maximumBytes)
        #expect(first.contains("SDK issues truncated: yes"))
    }

    @Test("Control characters, identifiers, and token-shaped versions never reach exports")
    func adversarialStringsAreOmitted() {
        let privateValues = [
            "26.0token", "26.0\nhostname", "26.0\rsecret", "26.0\u{0}token",
            "01234567-89AB-CDEF-0123-456789ABCDEF", "/Volumes/private/Xcode.app"
        ]
        for privateValue in privateValues {
            let snapshot = snapshot(
                versions: [privateValue],
                issues: [issue(privateValue), issue("platforms;android-36\nsecret")]
            )
            let report = DiagnosticReportBuilder.build(snapshot)
            #expect(!report.contains(privateValue))
            #expect(!report.contains("secret"))
            #expect(report.contains("Xcode A: unknown"))
        }
    }

    @Test("Metadata sizes and package identities are bounded")
    func boundedIssueFields() {
        let oversized = DiagnosticSDKIssue(
            category: .unknown,
            packageIdentity: "build-tools;" + String(repeating: "9", count: 100),
            sourcePropertiesStatus: .tooLarge,
            packageXMLStatus: .missing,
            identityMatchesLayout: false,
            reason: .oversizedMetadata,
            sourcePropertiesBytes: Int.max,
            packageXMLBytes: -1
        )
        let report = DiagnosticReportBuilder.build(snapshot(issues: [oversized]))
        #expect(report.contains("identity=omitted"))
        #expect(report.contains("sourceBytes=unknown, xmlBytes=unknown"))
        #expect(!report.contains(String(Int.max)))
    }

    @Test("Save preserves the exact preview text")
    func exportMatchesPreview() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("report-export-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let destination = root.appendingPathComponent("report.txt")
        let preview = DiagnosticReportBuilder.build(snapshot(issues: [issue("platforms;android-36")]))
        try await DiagnosticReportExporter.save(preview, to: destination)
        #expect(try String(contentsOf: destination, encoding: .utf8) == preview)
    }

    @Test("Oversized exports do not write a file")
    func oversizedExportRefused() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("report-limit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let destination = root.appendingPathComponent("report.txt")
        do {
            try await DiagnosticReportExporter.save(String(repeating: "x", count: 20_000), to: destination)
            Issue.record("Expected bounded export refusal")
        } catch is DiagnosticReportExportError {
            #expect(!FileManager.default.fileExists(atPath: destination.path))
        }
    }

    private func snapshot(versions: [String] = [], issues: [DiagnosticSDKIssue] = []) -> DiagnosticReportSnapshot {
        DiagnosticReportSnapshot(
            appVersion: "1.2.3", appBuild: "42", macOSVersion: "27.0", architecture: "arm64",
            toolchainResolution: .notChecked, toolchainSource: nil, xcodeVersions: versions,
            androidSDKRootSource: nil, sdkIssues: issues, sdkIssueCount: issues.count, sdkIssuesTruncated: false
        )
    }

    private func issue(_ identity: String) -> DiagnosticSDKIssue {
        DiagnosticSDKIssue(
            category: .systemImage,
            packageIdentity: identity,
            sourcePropertiesStatus: .malformed,
            packageXMLStatus: .missing,
            identityMatchesLayout: false,
            reason: .malformedXML,
            sourcePropertiesBytes: 128,
            packageXMLBytes: nil
        )
    }
}
