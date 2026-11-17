import CruftlessCore
import SwiftUI

/// Step 1: the app lives in the menu bar.
struct WelcomeLocationStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomeMenuBarIllustration()
            WelcomeHeading(
                "Cruftless lives in your menu bar",
                subtitle: Text(
                    """
                    There is no Dock icon and no main window. Click \(menuBarGlyph) at the top of your screen \
                    whenever you want to see what Xcode and Android tools have left on your disk.
                    """
                )
            )
            WelcomeCaption("A few quick things before the first scan. It takes about a minute.")
        }
    }

    private var menuBarGlyph: Image {
        Image("MenuBarIcon").renderingMode(.template)
    }
}

/// Step 2: what deleting means in this app.
struct WelcomeSafetyStep: View {
    private static let symbols = ["magnifyingglass", "trash", "flag"]

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            WelcomeHeading(
                "Nothing is deleted without you",
                subtitle: Text("Cruftless removes files for good, so it is careful about when.")
            )
            WelcomeCard {
                let promises = WelcomePolicy.safetyPromises
                ForEach(Array(promises.enumerated()), id: \.element.id) { index, promise in
                    if index > 0 {
                        Divider().padding(.leading, 60)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        Image(systemName: Self.symbols[index % Self.symbols.count])
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(.secondary)
                            .frame(width: 34, height: 34)
                            .background(.quaternary, in: .rect(cornerRadius: 10))
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promise.title)
                                .fontWeight(.semibold)
                            Text(promise.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(14)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// Step 4: what to scan and whether to start at login.
struct WelcomeSetupStep: View {
    let settings: SettingsModel
    let detected: DetectedPlatforms?

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 14) {
            WelcomeHeading(
                "Set it up your way",
                subtitle: Text("Preselected from what is installed on this Mac.")
            )
            WelcomeCard {
                platformRow(.apple, title: "Apple platforms")
                Divider().padding(.leading, 12)
                platformRow(.android, title: "Android")
            }
            WelcomeCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .fontWeight(.semibold)
                        WelcomeCaption(
                            "Keeps Cruftless in the menu bar after a restart. Without it, you open the app yourself each time."
                        )
                    }
                    Spacer(minLength: 0)
                    Toggle("Launch at login", isOn: $settings.isLaunchAtLoginEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                }
                .padding(12)
                if let message = settings.launchAtLoginError ?? settings.launchAtLoginNotice {
                    Divider().padding(.leading, 12)
                    HStack(spacing: 12) {
                        WelcomeCaption(message)
                        Spacer(minLength: 0)
                        if settings.launchAtLoginOffersSystemSettings {
                            Button("Open Login Items", action: settings.openLoginItemsSettings)
                                .controlSize(.small)
                        }
                    }
                    .padding(12)
                }
            }
            if let message = settings.platformSelectionError {
                WelcomeCaption(message)
            }
            WelcomeCaption("You can change all of this later in Settings.")
        }
    }

    private func platformRow(_ platform: DevelopmentPlatform, title: LocalizedStringKey) -> some View {
        Toggle(isOn: platformBinding(platform)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                WelcomeCaption(detected?.note(for: platform) ?? "Looking at this Mac")
            }
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(settings.isPlatformToggleDisabled(platform))
        .padding(12)
    }

    private func platformBinding(_ platform: DevelopmentPlatform) -> Binding<Bool> {
        Binding(
            get: { settings.platformSelection.platforms.contains(platform) },
            set: { settings.setPlatformEnabled(platform, $0) }
        )
    }
}
