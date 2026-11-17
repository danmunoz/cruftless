import Foundation

/// How this copy of Cruftless gets its updates.
public enum UpdateChannel: Sendable, Equatable {
    case homebrewCask
    case directDownload

    public static let caskroomPaths = [
        "/opt/homebrew/Caskroom/cruftless",
        "/usr/local/Caskroom/cruftless"
    ]

    public static let releasesURL = URL(string: "https://github.com/danmunoz/cruftless/releases")!
    public static let homebrewUpgradeCommand = "brew upgrade cruftless"

    /// Detects a Homebrew cask install from Caskroom existence checks alone, never listing a directory.
    public static func detect(
        pathExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) }
    ) -> UpdateChannel {
        caskroomPaths.contains(where: pathExists) ? .homebrewCask : .directDownload
    }

    /// The line above the update controls.
    public var summary: String {
        switch self {
        case .homebrewCask: "Updates ship through Homebrew."
        case .directDownload: "Download new versions from GitHub Releases."
        }
    }

    /// The command to copy, offered only for a cask install.
    public var upgradeCommand: String? {
        self == .homebrewCask ? Self.homebrewUpgradeCommand : nil
    }

    /// The note under a newer release, or nil when the release link is the whole story.
    public var availabilityNote: String? {
        self == .homebrewCask ? "The Homebrew update may take a little while to appear." : nil
    }
}
