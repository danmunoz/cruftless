import AppKit
import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// Owns the model and starts the work that must not wait for the popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()
    private(set) lazy var welcome = WelcomeModel(settings: model.settings, hasSavedInventory: model.hasSavedInventory)
    /// The access list the welcome shows, which is also the one Settings shows under Access.
    private(set) lazy var accessList: AccessListModel = {
        #if DEBUG
            if UserDefaults.standard.bool(forKey: DebugLaunch.accessFixture) {
                return .preview(PreviewFixtures.accessAreasMixed)
            }
        #endif
        return model.makeAccessListModel()
    }()

    func applicationDidFinishLaunching(_: Notification) {
        if welcome.isPending {
            model.isWelcomePending = true
            welcome.onFinish = { [model] in model.welcomeDidFinish() }
        }
        model.startAtLaunch()
    }

    /// Keeps a reopen from Finder or Spotlight from presenting the welcome again once it is done.
    func applicationShouldHandleReopen(_: NSApplication, hasVisibleWindows _: Bool) -> Bool {
        welcome.isPending
    }
}

struct CruftlessApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    private var model: AppModel { appDelegate.model }

    var body: some Scene {
        MenuBarExtra {
            MainView(model: model)
                .onAppear { model.popoverDidAppear() }
        } label: {
            Image(nsImage: Self.menuBarIcon)
        }
        .menuBarExtraStyle(.window)

        Window("Welcome to Cruftless", id: WelcomeWindow.id) {
            WelcomeView(model: appDelegate.welcome, accessList: appDelegate.accessList, app: appDelegate.model)
        }
        .defaultLaunchBehavior(appDelegate.welcome.isPending ? .presented : .suppressed)
        .restorationBehavior(.disabled)
        .windowResizability(.contentSize)
        .windowStyle(.hiddenTitleBar)

        Settings {
            SettingsView(
                settings: model.settings,
                simulatorToolchainResolver: .shared,
                appModel: model,
                accessModel: appDelegate.accessList
            )
        }
        .windowResizability(.contentSize)
    }

    private static let menuBarIcon: NSImage = {
        let image = NSImage(named: "MenuBarIcon") ?? NSImage(
            systemSymbolName: "internaldrive",
            accessibilityDescription: "Cruftless"
        ) ?? NSImage()
        image.size = NSSize(width: 18, height: 18)
        image.isTemplate = true
        return image
    }()
}
