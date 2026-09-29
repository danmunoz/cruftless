import Foundation

public struct ValidatedPath: Sendable, Hashable, CustomStringConvertible {
    public let url: URL

    public let path: String
    package let isRoot: Bool
    package let allowlistedRootPaths: [String]

    public var description: String {
        path
    }

    /// Internal initializer restricted to CruftlessCore.
    package init(
        validatedURL: URL,
        path: String,
        isRoot: Bool = false,
        allowlistedRootPaths: [String]
    ) {
        url = validatedURL
        self.path = path
        self.isRoot = isRoot
        self.allowlistedRootPaths = allowlistedRootPaths
    }
}
