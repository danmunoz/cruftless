import Foundation

public struct AndroidAVDInventoryItem: Sendable, Hashable {
    public let directory: URL
    public let registryPath: String
    public let registryName: String
    public let displayName: String
    public let systemImage: String?

    public init(
        directory: URL,
        registryPath: String = "",
        registryName: String = "",
        displayName: String,
        systemImage: String?
    ) {
        self.directory = directory
        self.registryPath = registryPath
        self.registryName = registryName
        self.displayName = displayName
        self.systemImage = systemImage
    }
}
