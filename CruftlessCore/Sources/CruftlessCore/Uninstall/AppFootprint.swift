import Darwin
import Foundation

/// Everything Cruftless writes outside its own bundle.
public struct AppFootprint: Sendable, Equatable {
    /// One folder a complete removal deletes.
    public struct Folder: Sendable, Equatable, Identifiable {
        public let id: String
        public let title: String
        public let url: URL
        public let consequence: String
    }

    public static let defaultBundleIdentifier = "com.danmunoz.Cruftless"
    public static let live = AppFootprint()

    public let bundleIdentifier: String
    public let home: URL
    public let userCacheDirectory: URL?

    public init(
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        bundleIdentifier: String = AppFootprint.defaultBundleIdentifier,
        userCacheDirectory: URL? = AppFootprint.darwinUserCacheDirectory()
    ) {
        self.home = home
        self.bundleIdentifier = bundleIdentifier
        self.userCacheDirectory = userCacheDirectory
    }

    /// The app's own Application Support folder: the saved scan and the prepared Android tools.
    public var applicationSupport: URL {
        library("Application Support/Cruftless")
    }

    public var caches: URL {
        library("Caches/\(bundleIdentifier)")
    }

    public var httpStorages: URL {
        library("HTTPStorages/\(bundleIdentifier)")
    }

    public var savedApplicationState: URL {
        library("Saved Application State/\(bundleIdentifier).savedState")
    }

    /// The preferences file, removed through `UserDefaults` rather than as a folder.
    public var preferencesFile: URL {
        home.appendingPathComponent("Library/Preferences/\(bundleIdentifier).plist", isDirectory: false)
    }

    /// The per-user cache folder macOS keeps under `/var/folders`, for Metal shader caches.
    public var userCache: URL? {
        userCacheDirectory?.appendingPathComponent(bundleIdentifier, isDirectory: true)
    }

    /// Every folder a complete removal deletes, in display order.
    public var folders: [Folder] {
        var folders = [
            Folder(
                id: "application-support",
                title: "Saved scan and Android tools",
                url: applicationSupport,
                consequence: "The last scan is forgotten and the Android command-line tools Cruftless downloaded are removed."
            ),
            Folder(
                id: "caches",
                title: "Caches",
                url: caches,
                consequence: "Cached update-check responses are removed."
            ),
            Folder(
                id: "http-storages",
                title: "Network storage",
                url: httpStorages,
                consequence: "Stored network state for the update check is removed."
            ),
            Folder(
                id: "saved-state",
                title: "Saved window state",
                url: savedApplicationState,
                consequence: "Saved window positions are removed."
            )
        ]
        if let userCache {
            folders.append(Folder(
                id: "user-cache",
                title: "System cache",
                url: userCache,
                consequence: "Graphics caches macOS kept for Cruftless are removed."
            ))
        }
        return folders
    }

    /// Reads `DARWIN_USER_CACHE_DIR` for the current user.
    public static func darwinUserCacheDirectory() -> URL? {
        var buffer = [CChar](repeating: 0, count: Int(PATH_MAX))
        let length = confstr(_CS_DARWIN_USER_CACHE_DIR, &buffer, buffer.count)
        guard length > 1, length <= buffer.count else { return nil }
        let bytes = buffer.prefix(length - 1).map { UInt8(bitPattern: $0) }
        guard let path = String(bytes: bytes, encoding: .utf8) else { return nil }
        return URL(fileURLWithPath: path, isDirectory: true)
    }

    private func library(_ relativePath: String) -> URL {
        home.appendingPathComponent("Library/\(relativePath)", isDirectory: true)
    }
}
