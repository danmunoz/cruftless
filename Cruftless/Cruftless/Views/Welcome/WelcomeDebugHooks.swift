import SwiftUI

extension View {
    /// Opens Settings on a named tab when a debug launch argument asks, so that window can be inspected.
    func debugOpensSettings(_ settings: SettingsModel) -> some View {
        #if DEBUG
            modifier(DebugOpensSettings(settings: settings))
        #else
            self
        #endif
    }
}

#if DEBUG
    /// Launch arguments that put a chosen screen on display without changing saved settings.
    enum DebugLaunch {
        static let openSettings = "cruftless.debug.openSettings"
        static let accessFixture = "cruftless.debug.accessFixture"
    }

    private struct DebugOpensSettings: ViewModifier {
        let settings: SettingsModel
        @Environment(\.openSettings) private var openSettings

        func body(content: Content) -> some View {
            content.task {
                guard let name = UserDefaults.standard.string(forKey: DebugLaunch.openSettings) else { return }
                settings.requestedSettingsSection = switch name {
                case "access": .access
                case "support": .support
                case "about": .about
                default: .general
                }
                openSettings()
            }
        }
    }
#endif
