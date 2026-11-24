import AppKit
import CruftlessCore
import SwiftUI

/// The last section of Support: how to remove Cruftless completely.
struct UninstallSection: View {
    let channel: UpdateChannel
    @Bindable var model: UninstallModel
    @State private var didCopy = false

    var body: some View {
        Section("Uninstall") {
            switch channel {
            case .homebrewCask:
                Text(Self.homebrewExplanation)
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Text(verbatim: UpdateChannel.homebrewZapCommand)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                    Spacer()
                    Button(didCopy ? "Copied" : "Copy", systemImage: didCopy ? "checkmark" : "doc.on.doc", action: copyCommand)
                }
            case .directDownload:
                Text(Self.directExplanation)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Remove Cruftless Data", role: .destructive, action: model.prepare)
            }
        }
        .sheet(isPresented: Binding(get: { model.isSheetPresented }, set: { if !$0 { model.cancel() } })) {
            UninstallSheet(model: model)
        }
    }

    private static let homebrewExplanation = """
    Cruftless was installed with Homebrew. This command removes the app with its data, settings, \
    login item and privacy permissions:
    """

    private static let directExplanation = """
    Removes the saved scan, caches, settings, login item, scan reminders and privacy permissions, \
    then quits. Drag Cruftless to the Trash afterwards.
    """

    private func copyCommand() {
        NSPasteboard.general.clearContents()
        didCopy = NSPasteboard.general.setString(UpdateChannel.homebrewZapCommand, forType: .string)
    }
}

#if DEBUG
    #Preview("Direct download") {
        Form { UninstallSection(channel: .directDownload, model: UninstallPreviewFixtures.model(.idle)) }
            .formStyle(.grouped)
            .frame(width: 520)
    }

    #Preview("Homebrew") {
        Form { UninstallSection(channel: .homebrewCask, model: UninstallPreviewFixtures.model(.idle)) }
            .formStyle(.grouped)
            .frame(width: 520)
    }
#endif
