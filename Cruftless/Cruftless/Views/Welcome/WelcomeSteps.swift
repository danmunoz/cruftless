import CruftlessCore
import SwiftUI

/// Step 1: the app lives in the menu bar.
struct WelcomeLocationStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
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
            WelcomeCaption("A few short steps come first. Nothing is measured until you start the scan.")
        }
    }

    private var menuBarGlyph: Image {
        Image("MenuBarIcon").renderingMode(.template)
    }
}

/// Step 2: what deleting means in this app.
struct WelcomeSafetyStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WelcomeHeading(
                "Nothing is deleted without you",
                subtitle: Text(WelcomePolicy.safetySummary)
            )
            WelcomeReviewIllustration()
            WelcomeCard {
                let promises = WelcomePolicy.safetyPromises
                ForEach(promises) { promise in
                    if promise.id != promises.first?.id {
                        Divider().padding(.leading, 56)
                    }
                    HStack(alignment: .center, spacing: 12) {
                        WelcomeSymbolTile(symbol: promise.symbol, tint: promise.isWarning ? .orange : nil)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(promise.title)
                                .fontWeight(.semibold)
                            Text(promise.detail)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
    }
}

/// A sketch of the Review step: what will go, the space it frees, and the one button that deletes.
struct WelcomeReviewIllustration: View {
    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text("Review")
                .font(.system(size: 11, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .leading)
                .padding(.top, 4)
            VStack(spacing: 0) {
                sketchRow(98, 36)
                Divider()
                sketchRow(76, 30)
                Divider()
                HStack(spacing: 0) {
                    WelcomeSketchBar(width: 84, height: 9, style: .init(.primary))
                    Spacer(minLength: 0)
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: 76, height: 20)
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 10))
            .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: .rect(cornerRadius: 14))
        .accessibilityElement()
        .accessibilityLabel("The Review step: a list of what will be deleted, the space it frees, and a Delete button")
    }

    private func sketchRow(_ name: CGFloat, _ size: CGFloat) -> some View {
        HStack(spacing: 0) {
            WelcomeSketchBar(width: name)
            Spacer(minLength: 0)
            WelcomeSketchBar(width: size)
        }
        .frame(height: 22)
    }
}

/// Step 3: what to scan and whether to start at login.
struct WelcomeSetupStep: View {
    let settings: SettingsModel
    let detected: DetectedPlatforms?

    var body: some View {
        @Bindable var settings = settings

        VStack(alignment: .leading, spacing: 12) {
            WelcomeHeading(
                "Choose what to scan",
                subtitle: Text("Preselected from what Cruftless found on this Mac. You can change all of this later in Settings.")
            )
            WelcomeSectionLabel("Platforms")
            WelcomeCard {
                platformRow(.apple, title: "Apple platforms")
                Divider().padding(.leading, 12)
                platformRow(.android, title: "Android")
            }
            if let message = settings.platformSelectionError {
                WelcomeCaption(message)
            }
            WelcomeSectionLabel("Menu bar")
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
