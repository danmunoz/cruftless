import Foundation
import ServiceManagement

public enum LaunchAtLoginPolicy: Sendable {
    public static func message(
        requested: Bool,
        status: SMAppService.Status,
        failure: String? = nil
    ) -> String? {
        guard requested else {
            // Disabling succeeds when the item is not enabled.
            return status == .enabled
                ? (failure ?? "Cruftless could not be removed from your login items.")
                : nil
        }

        switch status {
        case .enabled:
            return nil
        case .requiresApproval:
            return "Cruftless is waiting for approval in System Settings › General › Login Items."
        case .notFound:
            return "macOS can't find the Cruftless login item. Move Cruftless to Applications and try again."
        default:
            return failure ?? "Cruftless could not be registered to launch at login."
        }
    }
}

public enum ProtectedPathRejection: Sendable, Equatable {
    case volumeRoot
    case homeDirectory
    case alreadyCovered(ancestor: String)

    public var message: String {
        switch self {
        case .volumeRoot:
            "Protecting the whole startup disk would make Cruftless refuse every action it offers."
        case .homeDirectory:
            "Your home folder is already protected. Pick the specific folder you want to keep."
        case let .alreadyCovered(ancestor):
            "Already covered by \(ancestor)."
        }
    }
}

/// Vets a folder before it joins the protected list.
public enum ProtectedPathPolicy: Sendable {
    public static func rejection(
        for url: URL,
        home: URL = URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true),
        existing: [URL] = []
    ) -> ProtectedPathRejection? {
        let candidate = ProtectedPaths.normalize(url)
        guard candidate != "/" else { return .volumeRoot }
        guard candidate != ProtectedPaths.normalize(home) else { return .homeDirectory }

        let homePath = ProtectedPaths.normalize(home)
        for entry in existing {
            let ancestor = ProtectedPaths.normalize(entry)
            // The trailing slash enforces path-component boundaries.
            guard candidate == ancestor || candidate.hasPrefix(ancestor + "/") else { continue }
            return .alreadyCovered(ancestor: abbreviated(ancestor, home: homePath))
        }
        return nil
    }

    private static func abbreviated(_ path: String, home: String) -> String {
        if path == home { return "~" }
        guard path.hasPrefix(home + "/") else { return path }
        return "~" + path.dropFirst(home.count)
    }
}
