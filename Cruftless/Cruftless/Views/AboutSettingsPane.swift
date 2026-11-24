import AppKit
import CruftlessCore
import SwiftUI

public struct AboutSettingsPane: View {
    @State private var updateCheckState: AboutUpdateCheckState = .notChecked
    @State private var didCopyUpdateCommand = false
    @State private var updateChannel = UpdateChannel.detect()

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            AboutIdentity()
            AboutLinks()
            AboutUpdateSection(
                channel: updateChannel,
                state: $updateCheckState,
                didCopyCommand: $didCopyUpdateCommand,
                checkForUpdates: checkForUpdates
            )
        }
        .scenePadding()
        .padding(.vertical, 12)
    }

    private func checkForUpdates() {
        guard updateCheckState != .checking else { return }
        updateCheckState = .checking

        Task { @MainActor in
            do {
                switch try await CruftlessReleaseChecker().checkForUpdates() {
                case .upToDate:
                    updateCheckState = .upToDate
                case let .updateAvailable(release):
                    updateCheckState = .updateAvailable(release)
                }
            } catch {
                updateCheckState = .failed(CruftlessUpdateCheckFailure(error))
            }
        }
    }
}

private struct AboutIdentity: View {
    var body: some View {
        VStack(spacing: 6) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: 72, height: 72)
                .accessibilityHidden(true)

            Text("Cruftless")
                .font(.system(size: 17, weight: .semibold))

            if let version = CruftlessVersion.display() {
                Text(version)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Text("MIT License · © 2026 Daniel Munoz")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

private struct AboutLinks: View {
    var body: some View {
        VStack(spacing: 0) {
            AboutLink(
                title: "Project Website",
                destination: URL(string: "https://www.danmunoz.com/projects/cruftless")!
            )
            Divider()
                .padding(.leading, 12)
            AboutLink(
                title: "GitHub Repository",
                destination: URL(string: "https://github.com/danmunoz/cruftless")!
            )
            Divider()
                .padding(.leading, 12)
            AboutLink(
                title: "Acknowledgements",
                destination: URL(string: "https://github.com/danmunoz/cruftless#acknowledgements")!
            )
        }
        .background(.background.secondary, in: .rect(cornerRadius: 10))
        .overlay {
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(.separator)
        }
    }
}

private struct AboutLink: View {
    let title: LocalizedStringResource
    let destination: URL

    var body: some View {
        Link(destination: destination) {
            HStack(spacing: 6) {
                Text(title)
                Spacer(minLength: 12)
                Image(systemName: "arrow.up.right")
                    .imageScale(.small)
                    .foregroundStyle(.secondary)
            }
            .contentShape(.rect)
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
        }
        .buttonStyle(.plain)
    }
}

private enum AboutUpdateCheckState: Equatable {
    case notChecked
    case checking
    case upToDate
    case updateAvailable(CruftlessRelease)
    case failed(CruftlessUpdateCheckFailure)
}

private struct AboutUpdateSection: View {
    let channel: UpdateChannel
    @Binding var state: AboutUpdateCheckState
    @Binding var didCopyCommand: Bool
    let checkForUpdates: () -> Void
    @State private var copyReset: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 8) {
            Text(channel.summary)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let command = channel.upgradeCommand {
                HStack(spacing: 8) {
                    Text(verbatim: command)
                        .font(.system(.caption, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)

                    Button { copy(command) } label: {
                        Image(systemName: didCopyCommand ? "checkmark" : "doc.on.doc")
                            .imageScale(.small)
                            .frame(minWidth: 20, minHeight: 20)
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                    .help(didCopyCommand ? "Copied" : "Copy Homebrew update command")
                    .accessibilityLabel(didCopyCommand ? "Copied Homebrew update command" : "Copy Homebrew update command")
                }
            } else {
                Link("GitHub Releases", destination: UpdateChannel.releasesURL)
                    .font(.caption)
            }

            updateStatus
                .font(.caption)
                .foregroundStyle(.secondary)

            Button(action: checkForUpdates) {
                if state == .checking {
                    HStack(spacing: 6) {
                        ProgressView()
                            .controlSize(.small)
                        Text("Checking for Updates…")
                    }
                } else {
                    Text("Check for Updates")
                }
            }
            .disabled(state == .checking)
        }
        .multilineTextAlignment(.center)
        .onDisappear { copyReset?.cancel() }
    }

    @ViewBuilder
    private var updateStatus: some View {
        switch state {
        case .notChecked, .checking:
            EmptyView()
        case .upToDate:
            Text("Cruftless is up to date.")
        case let .updateAvailable(release):
            VStack(spacing: 4) {
                Text("Version \(release.version) is available.")
                Link("View Release", destination: release.releaseURL)
                if let note = channel.availabilityNote {
                    Text(note)
                }
            }
        case .failed(.installedVersionUnavailable):
            Text("This build has no release version, so Cruftless can’t compare it with the latest release.")
        case .failed(.checkFailed):
            Text("Couldn’t check for updates. Try again.")
        }
    }

    private func copy(_ command: String) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        didCopyCommand = pasteboard.setString(command, forType: .string)
        copyReset?.cancel()
        guard didCopyCommand else { return }
        copyReset = Task {
            try? await Task.sleep(for: Self.copyConfirmationLifetime)
            guard !Task.isCancelled else { return }
            didCopyCommand = false
        }
    }

    private static let copyConfirmationLifetime: Duration = .seconds(2)
}

#if DEBUG
    #Preview("About Settings") {
        AboutSettingsPane()
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("Update Available") {
        AboutUpdateSection(
            channel: .homebrewCask,
            state: .constant(.updateAvailable(AboutUpdatePreviewFixtures.release)),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Up to Date") {
        AboutUpdateSection(
            channel: .homebrewCask,
            state: .constant(.upToDate),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Checking for Updates") {
        AboutUpdateSection(
            channel: .homebrewCask,
            state: .constant(.checking),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Update Check Error") {
        AboutUpdateSection(
            channel: .homebrewCask,
            state: .constant(.failed(.checkFailed)),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Development Build") {
        AboutUpdateSection(
            channel: .homebrewCask,
            state: .constant(.failed(.installedVersionUnavailable)),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Direct Download") {
        AboutUpdateSection(
            channel: .directDownload,
            state: .constant(.notChecked),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Direct Download, Update Available") {
        AboutUpdateSection(
            channel: .directDownload,
            state: .constant(.updateAvailable(AboutUpdatePreviewFixtures.release)),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Command Copied") {
        AboutUpdateSection(
            channel: .homebrewCask,
            state: .constant(.notChecked),
            didCopyCommand: .constant(true),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }
#endif
