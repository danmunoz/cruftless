import AppKit
import CruftlessCore
import SwiftUI

public struct AboutSettingsPane: View {
    @State private var updateCheckState: AboutUpdateCheckState = .notChecked
    @State private var didCopyUpdateCommand = false

    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            AboutIdentity()
            AboutLinks()
            AboutUpdateSection(
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
                updateCheckState = .failed
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
    case failed
}

private struct AboutUpdateSection: View {
    @Binding var state: AboutUpdateCheckState
    @Binding var didCopyCommand: Bool
    let checkForUpdates: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text("Updates ship through Homebrew.")

            HStack(spacing: 8) {
                Text(verbatim: Self.updateCommand)
                    .font(.system(.caption, design: .monospaced))
                    .textSelection(.enabled)

                Button(action: copyUpdateCommand) {
                    Image(systemName: didCopyCommand ? "checkmark" : "doc.on.doc")
                        .imageScale(.small)
                        .frame(minWidth: 20, minHeight: 20)
                }
                .buttonStyle(.plain)
                .help(didCopyCommand ? "Copied" : "Copy Homebrew update command")
                .accessibilityLabel(didCopyCommand ? "Copied Homebrew update command" : "Copy Homebrew update command")
            }

            updateStatus

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
            .buttonStyle(.link)
            .disabled(state == .checking)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
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
                Text("The Homebrew update may take a little while to appear.")
            }
        case .failed:
            Text("Couldn’t check for updates. Try again.")
        }
    }

    private func copyUpdateCommand() {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        didCopyCommand = pasteboard.setString(Self.updateCommand, forType: .string)
    }

    private static let updateCommand = "brew upgrade cruftless"
}

#if DEBUG
    #Preview("About Settings") {
        AboutSettingsPane()
            .frame(width: SettingsMetrics.paneWidth)
    }

    #Preview("Update Available") {
        AboutUpdateSection(
            state: .constant(.updateAvailable(AboutUpdatePreviewFixtures.release)),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Up to Date") {
        AboutUpdateSection(
            state: .constant(.upToDate),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Checking for Updates") {
        AboutUpdateSection(
            state: .constant(.checking),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }

    #Preview("Update Check Error") {
        AboutUpdateSection(
            state: .constant(.failed),
            didCopyCommand: .constant(false),
            checkForUpdates: {}
        )
        .frame(width: SettingsMetrics.paneWidth)
        .padding()
    }
#endif
