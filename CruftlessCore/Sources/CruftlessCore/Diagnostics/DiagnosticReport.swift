import Foundation

public enum DiagnosticProbeStatus: String, Sendable, Hashable {
    case available
    case unavailable
    case ambiguous
    case notChecked
    case timedOut
}

public enum DiagnosticSDKCategory: String, Sendable, Hashable {
    case platform
    case sources
    case buildTools
    case systemImage
    case ndk
    case cmake
    case commandLineTools
    case emulator
    case platformTools
    case extras
    case unknown
}

public enum DiagnosticMetadataStatus: String, Sendable, Hashable {
    case valid
    case missing
    case unreadable
    case malformed
    case conflicting
    case unsupported
    case tooLarge
    case symlink
    case invalidEncoding
}

public enum DiagnosticSDKIssueReason: String, Sendable, Hashable {
    case unreadableMetadata
    case missingMetadata
    case oversizedMetadata
    case symlinkMetadata
    case invalidEncoding
    case malformedProperties
    case malformedXML
    case conflictingIdentity
    case nonRegularMetadata
    case unsupportedLayout
    case discoveryLimitReached
}

public struct DiagnosticSDKIssue: Sendable, Hashable {
    public let category: DiagnosticSDKCategory
    public let packageIdentity: String?
    public let sourcePropertiesStatus: DiagnosticMetadataStatus
    public let packageXMLStatus: DiagnosticMetadataStatus
    public let identityMatchesLayout: Bool
    public let reason: DiagnosticSDKIssueReason
    public let sourcePropertiesBytes: Int?
    public let packageXMLBytes: Int?

    public init(
        category: DiagnosticSDKCategory,
        packageIdentity: String?,
        sourcePropertiesStatus: DiagnosticMetadataStatus,
        packageXMLStatus: DiagnosticMetadataStatus,
        identityMatchesLayout: Bool,
        reason: DiagnosticSDKIssueReason,
        sourcePropertiesBytes: Int?,
        packageXMLBytes: Int?
    ) {
        self.category = category
        self.packageIdentity = packageIdentity
        self.sourcePropertiesStatus = sourcePropertiesStatus
        self.packageXMLStatus = packageXMLStatus
        self.identityMatchesLayout = identityMatchesLayout
        self.reason = reason
        self.sourcePropertiesBytes = Self.boundedSize(sourcePropertiesBytes)
        self.packageXMLBytes = Self.boundedSize(packageXMLBytes)
    }

    private static func boundedSize(_ size: Int?) -> Int? {
        guard let size, (0...65_536).contains(size) else { return nil }
        return size
    }
}

public struct DiagnosticReportSnapshot: Sendable, Hashable {
    public let appVersion: String?
    public let appBuild: String?
    public let macOSVersion: String?
    public let architecture: String?
    public let toolchainResolution: DiagnosticProbeStatus
    public let toolchainSource: SimulatorToolchainSource?
    public let xcodeVersions: [String]
    public let androidSDKRootSource: String?
    public let sdkIssues: [DiagnosticSDKIssue]
    public let sdkIssueCount: Int
    public let sdkIssuesTruncated: Bool

    public init(
        appVersion: String?,
        appBuild: String?,
        macOSVersion: String?,
        architecture: String?,
        toolchainResolution: DiagnosticProbeStatus,
        toolchainSource: SimulatorToolchainSource?,
        xcodeVersions: [String],
        androidSDKRootSource: String?,
        sdkIssues: [DiagnosticSDKIssue],
        sdkIssueCount: Int,
        sdkIssuesTruncated: Bool
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.macOSVersion = macOSVersion
        self.architecture = architecture
        self.toolchainResolution = toolchainResolution
        self.toolchainSource = toolchainSource
        self.xcodeVersions = xcodeVersions
        self.androidSDKRootSource = androidSDKRootSource
        self.sdkIssues = sdkIssues
        self.sdkIssueCount = sdkIssueCount
        self.sdkIssuesTruncated = sdkIssuesTruncated
    }
}

public enum DiagnosticReportBuilder {
    public static let maximumBytes = 16 * 1024
    public static let maximumSDKIssues = 64

    public static func build(_ snapshot: DiagnosticReportSnapshot) -> String {
        var lines = ["Cruftless Diagnostic Report", "Schema: 1"]
        lines.append("App version: \(version(snapshot.appVersion) ?? "unknown")")
        lines.append("App build: \(build(snapshot.appBuild) ?? "unknown")")
        lines.append("macOS: \(version(snapshot.macOSVersion) ?? "unknown")")
        lines.append("Architecture: \(architecture(snapshot.architecture))")
        lines.append("Simulator toolchain: \(snapshot.toolchainResolution.rawValue)")
        lines.append("Toolchain source: \(snapshot.toolchainSource?.rawValue ?? "unknown")")
        for (index, xcodeVersion) in snapshot.xcodeVersions.prefix(8).enumerated() {
            lines.append("Xcode \(label(index)): \(version(xcodeVersion) ?? "unknown")")
        }
        lines.append("Android SDK root source: \(sdkRootSource(snapshot.androidSDKRootSource))")
        lines.append("SDK issue count: \(max(0, snapshot.sdkIssueCount))")
        let issues = snapshot.sdkIssues.prefix(maximumSDKIssues)
        for (index, issue) in issues.enumerated() {
            let identity = standardPackageIdentity(issue.packageIdentity) ?? "omitted"
            lines.append(issueLine(index: index, issue: issue, identity: identity))
        }
        let truncated = snapshot.sdkIssuesTruncated || snapshot.sdkIssues.count > maximumSDKIssues
        lines.append("SDK issues truncated: \(truncated ? "yes" : "no")")
        lines.append(
            "Excluded: paths, usernames, hostnames, device identifiers, environment values, logs, metadata contents, and inventories."
        )
        let text = lines.joined(separator: "\n") + "\n"
        guard text.utf8.count > maximumBytes else { return text }
        let bytes = text.utf8.prefix(maximumBytes - 32)
        return String(bytes: bytes, encoding: .utf8)
            .map { $0 + "\nReport truncated.\n" }
            ?? "Cruftless Diagnostic Report\nReport truncated.\n"
    }

    private static func issueLine(index: Int, issue: DiagnosticSDKIssue, identity: String) -> String {
        let sourceBytes = issue.sourcePropertiesBytes.map(String.init) ?? "unknown"
        let xmlBytes = issue.packageXMLBytes.map(String.init) ?? "unknown"
        let match = issue.identityMatchesLayout ? "yes" : "no"
        return "SDK issue \(index + 1): category=\(issue.category.rawValue), identity=\(identity), " +
            "source=\(issue.sourcePropertiesStatus.rawValue), xml=\(issue.packageXMLStatus.rawValue), " +
            "sourceBytes=\(sourceBytes), xmlBytes=\(xmlBytes), reason=\(issue.reason.rawValue), layoutMatch=\(match)"
    }

    private static func version(_ raw: String?) -> String? {
        guard let raw, raw.count <= 32,
              raw.range(of: #"\A[0-9]+(?:\.[0-9]+){0,3}(?:(?:beta|rc)[0-9]+)?\z"#, options: .regularExpression) != nil
        else { return nil }
        return raw
    }

    private static func build(_ raw: String?) -> String? {
        guard let raw, raw.count <= 16,
              raw.range(of: #"\A[0-9]{1,16}\z"#, options: .regularExpression) != nil
        else { return nil }
        return raw
    }

    private static func architecture(_ raw: String?) -> String {
        switch raw {
        case "arm64": "arm64"
        case "x86_64": "x86_64"
        default: "unknown"
        }
    }

    private static func sdkRootSource(_ raw: String?) -> String {
        switch raw {
        case "ANDROID_HOME": "ANDROID_HOME"
        case "ANDROID_SDK_ROOT": "ANDROID_SDK_ROOT"
        case "Default Android SDK": "default"
        case nil: "unknown"
        default: "custom or unknown"
        }
    }

    private static func standardPackageIdentity(_ raw: String?) -> String? {
        guard let raw, raw.utf8.count <= 96,
              !raw.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains)
        else { return nil }
        let patterns = [
            #"\Aplatform-tools\z"#,
            #"\Aemulator\z"#,
            #"\Aplatforms;android-[0-9]{1,3}\z"#,
            #"\Abuild-tools;[0-9]+(?:\.[0-9]+){1,3}\z"#,
            #"\Asources;android-[0-9]{1,3}\z"#,
            #"\Andk;[0-9]+(?:\.[0-9]+){1,3}\z"#,
            #"\Acmake;[0-9]+(?:\.[0-9]+){1,3}\z"#,
            #"\Acmdline-tools;(?:latest|[0-9]+)\z"#,
            #"\Asystem-images;android-[0-9]{1,3};"# +
                #"(?:default|google_apis|google_apis_playstore|aosp_atd|google_atd);"# +
                #"(?:arm64-v8a|x86_64|x86|armeabi-v7a)\z"#
        ]
        return patterns.contains { raw.range(of: $0, options: .regularExpression) != nil } ? raw : nil
    }

    private static func label(_ index: Int) -> String {
        String(UnicodeScalar(65 + index) ?? "A")
    }
}
