import Foundation

public enum DrillDownContent: Sendable {
    case children([ChildEntry])
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
        if case let .children(children) = self { return children }
        return nil
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
