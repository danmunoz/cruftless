import CruftlessCore
import SwiftUI

/// Step 1: the app lives in the menu bar.
struct WelcomeLocationStep: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            WelcomeMenuBarIllustration()
            WelcomeHeading(
                "Cruftless lives in your menu bar",
                subtitle: Text("Click \(WelcomeInlineGlyph.text) to see what Xcode and Android tools left on your disk.")
            )
        }
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
                    .padding(.horizontal, WelcomeCardMetrics.inset)
                    .padding(.vertical, 10)
                    .accessibilityElement(children: .combine)
                }
            }
        }
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
                subtitle: Text("Preselected from this Mac. You can change it in Settings.")
            )
            WelcomeSectionLabel("Platforms")
            WelcomeCard {
                platformRow(.apple, title: "Apple platforms")
                Divider().padding(.leading, Self.platformTextInset)
                platformRow(.android, title: "Android")
            }
            if let message = settings.platformSelectionError {
                WelcomeCaption(message)
            }
            WelcomeSectionLabel("Startup")
            WelcomeCard {
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch at login")
                            .fontWeight(.semibold)
                        WelcomeCaption("Keeps Cruftless in the menu bar after a restart.")
                    }
                    Spacer(minLength: 0)
                    Toggle("Launch at login", isOn: $settings.isLaunchAtLoginEnabled)
                        .labelsHidden()
                        .toggleStyle(.switch)
                        .controlSize(.small)
                }
                .padding(.horizontal, WelcomeCardMetrics.inset)
                .padding(.vertical, 12)
                if let message = settings.launchAtLoginError ?? settings.launchAtLoginNotice {
                    Divider().padding(.leading, WelcomeCardMetrics.inset)
                    HStack(spacing: 12) {
                        WelcomeCaption(message)
                        Spacer(minLength: 0)
                        if settings.launchAtLoginOffersSystemSettings {
                            Button("Open Login Items", action: settings.openLoginItemsSettings)
                                .controlSize(.small)
                        }
                    }
                    .padding(.horizontal, WelcomeCardMetrics.inset)
                    .padding(.vertical, 12)
                }
            }
        }
    }

    private func platformRow(_ platform: DevelopmentPlatform, title: LocalizedStringKey) -> some View {
        Toggle(isOn: platformBinding(platform)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .fontWeight(.semibold)
                WelcomeCaption(detected?.note(for: platform) ?? "Checking this Mac")
            }
            .padding(.leading, 4)
        }
        .toggleStyle(.checkbox)
        .disabled(settings.isPlatformToggleDisabled(platform))
        .padding(.horizontal, WelcomeCardMetrics.inset)
        .padding(.vertical, 12)
    }

    /// Where a platform's title starts, past the checkbox.
    private static let platformTextInset: CGFloat = WelcomeCardMetrics.inset + 25

    private func platformBinding(_ platform: DevelopmentPlatform) -> Binding<Bool> {
        Binding(
            get: { settings.platformSelection.platforms.contains(platform) },
            set: { settings.setPlatformEnabled(platform, $0) }
        )
    }
}
