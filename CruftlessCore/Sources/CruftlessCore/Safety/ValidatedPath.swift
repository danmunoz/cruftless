import Foundation

public struct ValidatedPath: Sendable, Hashable, CustomStringConvertible {
    public let url: URL

    public let path: String

    public var description: String {
        path
    }

    /// Internal initializer restricted to CruftlessCore.
    package init(validatedURL: URL, path: String) {
        url = validatedURL
        self.path = path
    }
}
