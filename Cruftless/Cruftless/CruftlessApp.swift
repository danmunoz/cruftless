import AppKit
import CruftlessCore
import SwiftUI

/// Owns the model and starts the work that must not wait for the popover.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let model = AppModel()

    func applicationDidFinishLaunching(_: Notification) {
        model.startAtLaunch()
    }
}

@main
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

        Settings {
            SettingsView(settings: model.settings)
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
