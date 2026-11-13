import AppKit
import Combine
import CruftlessCore
import SwiftUI
import UniformTypeIdentifiers

public struct GeneralSettingsPane: View {
    public let settings: SettingsModel
    @State private var isFolderImporterPresented = false

    public init(settings: SettingsModel) {
        self.settings = settings
    }

    public var body: some View {
        @Bindable var settings = settings

        Form {
            Section {
                Toggle("Launch at login", isOn: $settings.isLaunchAtLoginEnabled)
                SettingsErrorRow(message: settings.launchAtLoginError)
                if let notice = settings.launchAtLoginNotice {
                    SettingsNoticeRow(message: notice)
                }
                if settings.launchAtLoginNeedsApproval {
                    Button("Open Login Items", action: settings.openLoginItemsSettings)
                }
            } header: {
                Text("Startup")
            } footer: {
                Text("Start Cruftless in the menu bar when you log in to your Mac.")
            }

            Section {
                Toggle("Weekly scan reminder", isOn: $settings.isScanReminderEnabled)
                SettingsErrorRow(message: settings.scanReminderError)
            } header: {
                Text("Reminders")
            } footer: {
                Text("The reminder is a weekly local notification and never scans your disk.")
            }

            Section {
                Toggle("Apple development", isOn: platformBinding(.apple))
                    .disabled(settings.isPlatformToggleDisabled(.apple))
                Toggle("Android development", isOn: platformBinding(.android))
                    .disabled(settings.isPlatformToggleDisabled(.android))
                SettingsErrorRow(message: settings.platformSelectionError)
            } header: {
                Text("Platforms to Scan")
            } footer: {
                Text(
                    "Android includes shared Gradle caches that other projects may use. "
                        + "SDK and Android Studio storage is read-only. "
                        + "Deleting devices needs the Android tools. "
                        + "Gradle cleanup asks for an extra risk review."
                )
            }

            if settings.showsPlatformOrder {
                Section {
                    Picker("Show first", selection: $settings.platformSectionOrder) {
                        Text("Apple development").tag(PlatformSectionOrder.appleFirst)
                        Text("Android development").tag(PlatformSectionOrder.androidFirst)
                    }
                    .pickerStyle(.segmented)
                } header: {
                    Text("Main Page Order")
                } footer: {
                    Text("Choose which platform section appears first in the main list.")
                }
            }

            ProtectedPathsSection(
                paths: settings.protectedPaths,
                errorMessage: settings.protectedPathError,
                isEditable: settings.canEditProtectedPaths,
                onAdd: { isFolderImporterPresented = true },
                onRemove: settings.removeProtectedPath
            )
        }
        .formStyle(.grouped)
        .fileImporter(
            isPresented: $isFolderImporterPresented,
            allowedContentTypes: [.folder],
            allowsMultipleSelection: false,
            onCompletion: handleFolderSelection
        )
        .onAppear { settings.refreshSystemState() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            settings.refreshSystemState()
        }
        .settingsPaneSizing(estimate: 700, cap: 800)
    }

    private func platformBinding(_ platform: DevelopmentPlatform) -> Binding<Bool> {
        Binding(
            get: { settings.platformSelection.platforms.contains(platform) },
            set: { settings.setPlatformEnabled(platform, $0) }
        )
    }

    private func handleFolderSelection(_ result: Result<[URL], any Error>) {
        switch result {
        case let .success(urls):
            if let url = urls.first { settings.addProtectedPath(url) }
        case let .failure(error):
            settings.reportFolderPickerFailure(error)
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

private struct SettingsNoticeRow: View {
    let message: String

    var body: some View {
        Label(message, systemImage: "info.circle.fill")
            .foregroundStyle(.secondary)
            .font(.callout)
    }
}

private struct ProtectedPathsSection: View {
    let paths: [URL]
    let errorMessage: String?
    let isEditable: Bool
    let onAdd: () -> Void
    let onRemove: (URL) -> Void

    var body: some View {
        Section {
            if paths.isEmpty {
                Text("No protected folders")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(paths, id: \.self) { path in
                    ProtectedPathRow(path: path, isEnabled: isEditable) { onRemove(path) }
                }
            }

            Button("Add Folder…", action: onAdd)
                .disabled(!isEditable)
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
    let isEnabled: Bool
    let onRemove: () -> Void

    var body: some View {
        LabeledContent {
            Button(action: onRemove) {
                Image(systemName: "minus.circle.fill")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.borderless)
            .disabled(!isEnabled)
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
        GeneralSettingsPane(settings: SettingsPreviewFixtures.errors)
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("General Settings: Protected paths") {
        GeneralSettingsPane(settings: .preview(protectedPaths: SettingsPreviewFixtures.protectedPaths))
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("General Settings: Login approval pending") {
        GeneralSettingsPane(settings: SettingsPreviewFixtures.pendingApproval)
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("General Settings: Deletion running") {
        GeneralSettingsPane(settings: SettingsPreviewFixtures.deletionRunning)
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("General Settings: Platform selection refused") {
        GeneralSettingsPane(settings: SettingsPreviewFixtures.platformSelectionRefused)
            .frame(width: SettingsMetrics.paneWidth)
    }
#endif
