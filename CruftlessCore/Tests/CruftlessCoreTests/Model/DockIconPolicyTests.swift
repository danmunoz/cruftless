import CruftlessCore
import Testing

@Suite("Dock icon policy")
struct DockIconPolicyTests {
    private typealias Window = DockIconPolicy.WindowState

    private static let welcome = Window(isVisible: true, isMiniaturized: false, canBecomeMain: true)
    private static let popover = Window(isVisible: true, isMiniaturized: false, canBecomeMain: false)
    private static let closed = Window(isVisible: false, isMiniaturized: false, canBecomeMain: true)

    @Test("No windows, no Dock icon")
    func noWindows() {
        #expect(!DockIconPolicy.showsDockIcon(for: []))
    }

    @Test("An open welcome or Settings window shows the Dock icon")
    func openWindow() {
        #expect(DockIconPolicy.showsDockIcon(for: [Self.welcome]))
        #expect(DockIconPolicy.showsDockIcon(for: [Self.popover, Self.welcome]))
    }

    @Test("The popover alone never shows the Dock icon")
    func popoverOnly() {
        #expect(!DockIconPolicy.showsDockIcon(for: [Self.popover]))
    }

    @Test("A closed window hides the Dock icon")
    func closedWindow() {
        #expect(!DockIconPolicy.showsDockIcon(for: [Self.closed, Self.popover]))
    }

    @Test("A minimized window keeps the Dock icon so it can be restored")
    func minimizedWindow() {
        let minimized = Window(isVisible: false, isMiniaturized: true, canBecomeMain: true)
        #expect(DockIconPolicy.showsDockIcon(for: [minimized]))
    }
}
