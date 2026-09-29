import AppKit
import Combine
import CruftlessCore
import SwiftUI

public struct GeneralSettingsPane: View {
    public let settings: SettingsModel

    public init(settings: SettingsModel) {
        self.settings = settings
    }

    public var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.isLaunchAtLoginEnabled)
                SettingsErrorRow(message: settings.launchAtLoginError)
            } header: {
                Text("Startup")
            } footer: {
                Text("Start Cruftless in the menu bar when you log in to your Mac.")
            }

            Section {
                Toggle("Weekly scan reminder", isOn: $settings.isScanReminderEnabled)
                SettingsErrorRow(message: settings.scanReminderError)
            } header: {
                Text("Scanning")
            } footer: {
                Text("The reminder is a weekly local notification and never scans your disk.")
            }

            Section {
                Toggle("Apple development", isOn: platformBinding(.apple))
                    .disabled(cannotDisable(.apple))
                Toggle("Android development", isOn: platformBinding(.android))
                    .disabled(cannotDisable(.android))
                SettingsErrorRow(message: settings.platformSelectionError)
            } header: {
                Text("Platforms to scan")
            } footer: {
                Text(
                    "Android includes shared Gradle caches that can affect non-Android projects. " +
                        "SDK, AVD, and Android Studio storage is read-only; Gradle cache cleanup requires a risk review."
                )
            }

            if showsPlatformOrder {
                Section {
                    Picker("Show first", selection: $settings.platformSectionOrder) {
                        Text("Apple development").tag(PlatformSectionOrder.appleFirst)
                        Text("Android development").tag(PlatformSectionOrder.androidFirst)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Main page order")
                } footer: {
                    Text("Choose which platform section appears first in the main list.")
                }
            }

            ProtectedPathsSection(
                paths: settings.protectedPaths,
                errorMessage: settings.protectedPathError,
                onAdd: chooseFolder,
                onRemove: settings.removeProtectedPath
            )
        }
        .formStyle(.grouped)
        .onAppear { settings.refreshLaunchAtLoginStatus() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshLaunchAtLoginStatus()
        }
        .frame(height: SettingsMetrics.generalPaneHeight(
            protectedPathCount: settings.protectedPaths.count,
            errorRowCount: settings.visibleErrorRowCount,
            includesPlatformSelection: true,
            includesPlatformOrder: showsPlatformOrder
        ))
    }

    private var showsPlatformOrder: Bool {
        settings.platformSelection.platforms == Set(DevelopmentPlatform.allCases)
    }

    private func platformBinding(_ platform: DevelopmentPlatform) -> Binding<Bool> {
        Binding(
            get: { settings.platformSelection.platforms.contains(platform) },
            set: { settings.setPlatformEnabled(platform, $0) }
        )
    }

    private func cannotDisable(_ platform: DevelopmentPlatform) -> Bool {
        settings.isDeletionExecuting ||
            (settings.platformSelection.platforms.count == 1 && settings.platformSelection.platforms.contains(platform))
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.prompt = "Protect Folder"

        if panel.runModal() == .OK, let url = panel.url {
            settings.addProtectedPath(url)
        }
    }
}

private struct SettingsErrorRow: View {
    let message: String?

    var body: some View {
        if let message {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
                .font(.callout)
        }
    }
}

private struct ProtectedPathsSection: View {
    let paths: [URL]
    let errorMessage: String?
    let onAdd: () -> Void
    let onRemove: (URL) -> Void

    var body: some View {
        Section {
            if paths.isEmpty {
                Text("No protected folders")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paths, id: \.self) { path in
                    ProtectedPathRow(path: path) { onRemove(path) }
                }
            }

            Button("Add Folder…", action: onAdd)
            SettingsErrorRow(message: errorMessage)
        } header: {
            Text("Protected Paths")
        } footer: {
            Text("Cruftless refuses to delete these folders or anything inside them.")
        }
    }
}

private struct ProtectedPathRow: View {
    let path: URL
    let onRemove: () -> Void

    var body: some View {
        LabeledContent {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .help("Stop protecting this folder")
            .accessibilityLabel("Stop protecting \(path.lastPathComponent)")
        } label: {
            Label {
                VStack(alignment: .leading, spacing: 1) {
                    Text(path.lastPathComponent)
                    Text(abbreviatedPath)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.head)
                }
            } icon: {
                Image(systemName: "folder")
                    .foregroundStyle(.secondary)
            }
        }
        .help(path.path)
    }

    private var abbreviatedPath: String {
        (path.path as NSString).abbreviatingWithTildeInPath
    }
}

#if DEBUG
    #Preview("General Settings: Default") {
        GeneralSettingsPane(settings: .preview())
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("General Settings: Errors") {
        GeneralSettingsPane(settings: .preview(
            launchAtLoginError: "Cruftless is waiting for approval in System Settings › General › Login Items.",
            scanReminderError: "Notifications are turned off for Cruftless. "
                + "Allow them in System Settings › Notifications.",
            protectedPathError: ProtectedPathRejection.volumeRoot.message
        ))
        .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("General Settings: Protected paths") {
        GeneralSettingsPane(settings: .preview(protectedPaths: [
            URL(fileURLWithPath: "/Users/daniel/Developer/ImportantProject"),
            URL(fileURLWithPath: "/Users/daniel/Desktop/ReleaseArtifacts")
        ]))
        .frame(width: SettingsMetrics.paneWidth)
    }
#endif
