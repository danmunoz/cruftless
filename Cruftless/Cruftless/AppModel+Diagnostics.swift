import CruftlessCore

@MainActor
extension AppModel {
    var androidSDKReportData: AndroidSDKReportData {
        let content = drillDowns[LocationCatalog.androidSDK.id]
        let diagnostics = content?.androidSDKDiagnostics ?? []
        let issues = diagnostics.map { diagnostic in
            DiagnosticSDKIssue(
                category: diagnostic.category,
                packageIdentity: diagnostic.packageIdentity,
                sourcePropertiesStatus: diagnostic.sourcePropertiesStatus,
                packageXMLStatus: diagnostic.packageXMLStatus,
                identityMatchesLayout: diagnostic.identityMatchesLayout,
                reason: Self.reportReason(for: diagnostic.reason),
                sourcePropertiesBytes: diagnostic.sourcePropertiesBytes,
                packageXMLBytes: diagnostic.packageXMLBytes
            )
        }
        let root = inventory?.entries.first(where: { $0.id == LocationCatalog.androidSDK.id })?.roots.first?.url
        let source = root.map { RootResolver.androidRootSource(locationID: LocationCatalog.androidSDK.id, root: $0) }
        return AndroidSDKReportData(
            rootSource: source,
            issues: issues,
            count: content?.androidSDKDiagnosticCount ?? 0,
            truncated: content?.androidSDKDiagnosticsTruncated ?? false
        )
    }

    private static func reportReason(for reason: AndroidSDKDiagnosticReason) -> DiagnosticSDKIssueReason {
        DiagnosticSDKIssueReason(rawValue: reason.rawValue) ?? .unsupportedLayout
    }
}

struct AndroidSDKReportData {
    let rootSource: String?
    let issues: [DiagnosticSDKIssue]
    let count: Int
    let truncated: Bool
}
