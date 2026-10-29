import CruftlessCore
import SwiftUI

struct AndroidToolsSetupView: View {
    let child: ChildEntry
    @Bindable var model: AppModel

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: "Android tools", backTitle: "Android devices", onBack: model.cancelAndroidTools)
            Hairline()
            VStack(alignment: .leading, spacing: 14) {
                Text(child.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(child.url.path(percentEncoded: false))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                switch model.androidToolsStage {
                case .checking:
                    ProgressView("Checking Android tools…")
                case .installing:
                    ProgressView("Setting up Android tools…")
                    Text("The download and first-run setup may take a few minutes.")
                        .font(.callout).foregroundStyle(.secondary)
                case .needsSetup:
                    Text("Set up Android tools?").font(.title3.weight(.semibold))
                    Text(
                        "Cruftless needs Google's Android CLI to remove this device. With your permission, "
                            + "it will download missing tools and prepare their runtime. This may use network access and disk space."
                    )
                    .font(.callout)
                    Text("You will review the device deletion separately after setup. No device is deleted by installing tools.")
                        .font(.callout).foregroundStyle(.secondary)
                case let .failed(reason):
                    NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: reason)
                }
                Spacer(minLength: 0)
            }
            .padding(PopoverMetrics.bandInset)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            PopoverFooter {
                HStack {
                    Button("Cancel", action: model.cancelAndroidTools)
                        .buttonStyle(.glass).controlSize(.large)
                        .keyboardShortcut(.cancelAction)
                    Spacer()
                    if model.androidToolsStage == .needsSetup {
                        Button("Install Tools") { model.installAndroidTools(for: child) }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    }
                    if case .failed = model.androidToolsStage {
                        Button("Try Again") { model.retryAndroidAVDPreparation(child) }
                            .buttonStyle(.glass).controlSize(.large)
                    }
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Android tools: installation consent") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device, model: AndroidToolsPreviewFixtures.model(.needsSetup))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Android tools: checking") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device, model: AndroidToolsPreviewFixtures.model(.checking))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Android tools: downloading") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device, model: AndroidToolsPreviewFixtures.model(.installing))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Android tools: active device") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device,
                              model: AndroidToolsPreviewFixtures
                                  .model(.failed("This emulator is active. Shut it down before deleting its device.")))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Android tools: unknown activity") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device,
                              model: AndroidToolsPreviewFixtures.model(.failed("The emulator's activity could not be checked. Try again.")))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
    #Preview("Android tools: installation failed") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device,
                              model: AndroidToolsPreviewFixtures.model(.failed("Android tools could not be downloaded. Try again.")))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
