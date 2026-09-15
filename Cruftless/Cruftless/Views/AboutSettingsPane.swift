import AppKit
import CruftlessCore
import SwiftUI

public struct AboutSettingsPane: View {
    public init() {}

    public var body: some View {
        VStack(spacing: 20) {
            AboutIdentity()
            AboutLinks()
            AboutUpdateNote()
        }
        .scenePadding()
        .padding(.vertical, 12)
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

private struct AboutUpdateNote: View {
    var body: some View {
        VStack(spacing: 4) {
            Text("Updates ship through Homebrew.")
            Text(verbatim: "brew upgrade cruftless")
                .font(.system(.caption, design: .monospaced))
                .textSelection(.enabled)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .multilineTextAlignment(.center)
    }
}

#if DEBUG
    #Preview("About Settings") {
        AboutSettingsPane()
            .frame(width: SettingsMetrics.paneWidth)
    }
#endif
