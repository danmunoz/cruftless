/// Decides when the menu bar app shows a Dock icon: while one of its own windows is open.
public enum DockIconPolicy {
    /// The parts of a window's state the decision reads.
    public struct WindowState: Equatable, Sendable {
        public var isVisible: Bool
        public var isMiniaturized: Bool
        /// False for the popover panel and status item windows, true for the welcome and Settings.
        public var canBecomeMain: Bool

        public init(isVisible: Bool, isMiniaturized: Bool, canBecomeMain: Bool) {
            self.isVisible = isVisible
            self.isMiniaturized = isMiniaturized
            self.canBecomeMain = canBecomeMain
        }
    }

    /// True while a window that can become main is on screen or minimized to the Dock.
    public static func showsDockIcon(for windows: [WindowState]) -> Bool {
        windows.contains { $0.canBecomeMain && ($0.isVisible || $0.isMiniaturized) }
    }
}
