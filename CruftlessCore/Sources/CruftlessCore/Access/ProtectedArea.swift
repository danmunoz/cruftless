import Foundation

/// A place macOS guards with a privacy alert the first time an app opens a file or lists a folder in it.
public enum ProtectedArea: String, Sendable, Hashable, Codable, CaseIterable {
    case documents
    case desktop
    case downloads
    /// iCloud Drive and other file provider domains.
    case fileProvider
    case removableVolume
    case networkVolume

    /// The name the user knows the area by.
    public var displayName: String {
        switch self {
        case .documents: "Documents"
        case .desktop: "Desktop"
        case .downloads: "Downloads"
        case .fileProvider: "iCloud Drive"
        case .removableVolume: "an external drive"
        case .networkVolume: "a network volume"
        }
    }

    /// The name as a heading: "External Drive" rather than "an external drive".
    public var title: String {
        switch self {
        case .removableVolume: "External Drive"
        case .networkVolume: "Network Volume"
        default: displayName
        }
    }
}

/// Whether macOS has already shown its alert for an area.
public enum AreaAccessState: String, Sendable, Hashable, Codable {
    /// Cruftless has never opened anything there, so the next open would raise an alert.
    case notAsked
    /// The user answered the alert and macOS refuses the read.
    case notAllowed
}
