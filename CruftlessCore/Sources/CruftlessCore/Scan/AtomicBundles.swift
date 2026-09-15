import Foundation

public enum AtomicBundles: Sendable {
    public static let extensions: Set<String> = [
        "app",
        "xcodeproj",
        "xcarchive",
        "xcworkspace"
    ]

    public static func isAtomicBundle(_ url: URL) -> Bool {
        extensions.contains(url.pathExtension.lowercased())
    }
}
