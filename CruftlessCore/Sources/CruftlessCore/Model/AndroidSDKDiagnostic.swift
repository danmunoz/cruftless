import Foundation

public enum AndroidSDKDiagnosticReason: String, Sendable, Hashable {
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

    public var message: String {
        switch self {
        case .unreadableMetadata: "Package metadata could not be read."
        case .missingMetadata: "Package identity metadata is missing."
        case .oversizedMetadata: "Package metadata exceeds the supported size limit."
        case .symlinkMetadata: "Package metadata is a symbolic link and was not followed."
        case .invalidEncoding: "Package metadata is not supported UTF-8 text."
        case .malformedProperties: "Package properties could not be parsed."
        case .malformedXML: "Package XML could not be parsed safely."
        case .conflictingIdentity: "Package metadata conflicts with its directory layout or another metadata file."
        case .nonRegularMetadata: "Package metadata is not a regular file."
        case .unsupportedLayout: "Some SDK contents are outside the supported package layouts."
        case .discoveryLimitReached: "SDK discovery reached its bounded directory or entry limit."
        }
    }
}

public struct AndroidSDKDiagnostic: Sendable, Hashable, Identifiable {
    public var id: String {
        "\(relativePath):\(reason.rawValue)"
    }

    /// Relative to the SDK root and intended for local inspection only.
    public let relativePath: String
    public let category: DiagnosticSDKCategory
    public let packageIdentity: String?
    public let reason: AndroidSDKDiagnosticReason
    public let sourcePropertiesStatus: DiagnosticMetadataStatus
    public let packageXMLStatus: DiagnosticMetadataStatus
    public let sourcePropertiesBytes: Int?
    public let packageXMLBytes: Int?
    public let identityMatchesLayout: Bool

    public init(
        relativePath: String,
        category: DiagnosticSDKCategory,
        packageIdentity: String? = nil,
        reason: AndroidSDKDiagnosticReason,
        sourcePropertiesStatus: DiagnosticMetadataStatus,
        packageXMLStatus: DiagnosticMetadataStatus,
        identityMatchesLayout: Bool,
        sourcePropertiesBytes: Int? = nil,
        packageXMLBytes: Int? = nil
    ) {
        self.relativePath = relativePath
        self.category = category
        self.packageIdentity = packageIdentity
        self.reason = reason
        self.sourcePropertiesStatus = sourcePropertiesStatus
        self.packageXMLStatus = packageXMLStatus
        self.identityMatchesLayout = identityMatchesLayout
        self.sourcePropertiesBytes = sourcePropertiesBytes.flatMap { (0 ... 65536).contains($0) ? $0 : nil }
        self.packageXMLBytes = packageXMLBytes.flatMap { (0 ... 65536).contains($0) ? $0 : nil }
    }
}
