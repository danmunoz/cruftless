import Foundation

public struct AndroidSDKPackage: Sendable, Hashable {
    public let displayName: String
    public let packagePath: String?
    public let revision: String?

    public init(displayName: String, packagePath: String?, revision: String?) {
        self.displayName = displayName
        self.packagePath = packagePath
        self.revision = revision
    }
}
