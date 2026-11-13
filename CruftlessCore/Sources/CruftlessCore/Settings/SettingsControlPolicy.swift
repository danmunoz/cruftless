import Foundation

/// Which General settings controls may change, and what a locked control reports.
public enum SettingsControlPolicy: Sendable {
    public static let platformSelectionBusyMessage = "Platform selection is unavailable while a deletion is running."
    public static let protectedPathsBusyMessage = "Protected paths cannot change while a deletion is running."

    /// A platform stays on while it is the only one selected, and every toggle locks during a deletion.
    public static func isPlatformToggleDisabled(
        _ platform: DevelopmentPlatform,
        selection: PlatformSelection,
        isDeletionExecuting: Bool
    ) -> Bool {
        isDeletionExecuting || (selection.platforms == [platform])
    }

    /// The selection after switching `platform`; nil when the change is refused or changes nothing.
    public static func updatedSelection(
        from selection: PlatformSelection,
        platform: DevelopmentPlatform,
        enabled: Bool
    ) -> PlatformSelection? {
        var platforms = selection.platforms
        if enabled {
            platforms.insert(platform)
        } else {
            guard platforms.contains(platform), platforms.count > 1 else { return nil }
            platforms.remove(platform)
        }
        let updated = PlatformSelection(platforms)
        return updated == selection ? nil : updated
    }

    /// The order picker only matters while both platforms are listed.
    public static func showsPlatformOrder(for selection: PlatformSelection) -> Bool {
        selection.platforms == Set(DevelopmentPlatform.allCases)
    }

    public static func allowsProtectedPathEdits(isDeletionExecuting: Bool) -> Bool {
        !isDeletionExecuting
    }

    /// Drops a message that only reported a running deletion, keeping every other message.
    public static func clearingBusyMessage(_ message: String?) -> String? {
        switch message {
        case platformSelectionBusyMessage, protectedPathsBusyMessage: nil
        default: message
        }
    }
}
