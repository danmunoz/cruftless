import Foundation

public enum DrillDownContent: Sendable {
    case children([ChildEntry])
    case childrenWithIssue([ChildEntry], String)
    case childrenWithDiagnostics([ChildEntry], summary: String, [AndroidSDKDiagnostic], totalCount: Int, truncated: Bool)
    case devices([SimDevice], sizes: [String: Int64])
    case runtimes([SimRuntime])
    /// A source that answered with an error: `simctl` failing, a root that vanished between resolving and reading it.
    case unavailable(String)

    /// Whether this is worth showing at all.
    public var isUnavailable: Bool {
        failureReason != nil
    }

    public var failureReason: String? {
        if case let .unavailable(reason) = self { return reason }
        return nil
    }

    public var children: [ChildEntry]? {
        switch self {
        case let .children(children), let .childrenWithIssue(children, _),
             let .childrenWithDiagnostics(children, _, _, _, _): children
        default: nil
        }
    }

    public var inventoryIssue: String? {
        switch self {
        case let .childrenWithIssue(_, issue), let .childrenWithDiagnostics(_, issue, _, _, _): issue
        default: nil
        }
    }

    public var androidSDKDiagnostics: [AndroidSDKDiagnostic] {
        if case let .childrenWithDiagnostics(_, _, diagnostics, _, _) = self { return diagnostics }
        return []
    }

    public var androidSDKDiagnosticCount: Int {
        if case let .childrenWithDiagnostics(_, _, _, count, _) = self { return count }
        return 0
    }

    public var androidSDKDiagnosticsTruncated: Bool {
        if case let .childrenWithDiagnostics(_, _, _, _, truncated) = self { return truncated }
        return false
    }

    public var runtimes: [SimRuntime]? {
        if case let .runtimes(runtimes) = self { return runtimes }
        return nil
    }

    public var devices: (devices: [SimDevice], sizes: [String: Int64])? {
        if case let .devices(devices, sizes) = self { return (devices, sizes) }
        return nil
    }
}
