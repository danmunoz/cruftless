import AppKit

/// Brings this agent app in front with the forced request, since macOS refuses its plain `NSApp.activate()`.
@MainActor
enum AppActivation {
    /// Makes the app active whichever app is active now.
    static func activate() {
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Activates the app and raises its open windows, and does nothing when none is open.
    static func bringOpenWindowsForward() {
        let windows = NSApp.windows.filter { $0.isVisible && $0.canBecomeMain }
        guard !windows.isEmpty else { return }
        activate()
        for window in windows {
            window.orderFront(nil)
        }
    }
}
