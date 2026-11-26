import CruftlessCore
import SwiftUI

struct AndroidToolsSetupView: View {
    let child: ChildEntry
    @Bindable var model: AppModel

    private var kind: AndroidRemovalKind {
        AndroidRemovalKind(child: child)
    }

    private var subject: String {
        kind == .sdkPackage ? "package" : "device"
    }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: "Android tools", backTitle: kind == .sdkPackage ? "Android SDK" : "Android devices",
                          onBack: model.cancelAndroidTools)
            Hairline()
            VStack(alignment: .leading, spacing: 14) {
                Text(child.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
                Text(child.url.path(percentEncoded: false))
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)
                stageContent
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
                    switch model.androidToolsStage {
                    case .needsSetup:
                        Button("Install Tools") { model.installAndroidTools(for: child) }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    case .needsUpdate:
                        Button("Download Latest") { model.installAndroidTools(for: child) }
                            .buttonStyle(.glassProminent).controlSize(.large)
                    case .failed:
                        Button("Try Again") { model.retryAndroidPreparation(child) }
                            .buttonStyle(.glass).controlSize(.large)
                    case .checking, .installing:
                        EmptyView()
                    }
                }
            }
        }
    }

    @ViewBuilder private var stageContent: some View {
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
                "Cruftless needs Google's Android CLI to remove this \(subject). With your permission, "
                    + "it will download missing tools and prepare their runtime. This may use network access and disk space."
            )
            .font(.callout)
            Text("You will review the \(subject) removal separately after setup. Installing tools removes nothing.")
                .font(.callout).foregroundStyle(.secondary)
        case let .needsUpdate(installed):
            Text("Update Android tools?").font(.title3.weight(.semibold))
            Text(
                "Removing SDK packages needs Android tools \(AndroidCLIVersion.minimumForSDKRemoval) or later"
                    + (installed.map { "; \($0) is set up." } ?? ".")
                    + " Cruftless will download Google's latest release into its own folder."
            )
            .font(.callout)
            Text("Your existing copy stays as it is. You will review the package removal separately afterwards.")
                .font(.callout).foregroundStyle(.secondary)
        case let .failed(reason):
            NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: reason)
        }
    }
}

#if DEBUG
    #Preview("Android tools: installation consent") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.device, model: AndroidToolsPreviewFixtures.model(.needsSetup))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Android tools: SDK package consent") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.sdkPackage, model: AndroidToolsPreviewFixtures.model(.needsSetup))
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Android tools: update for SDK packages") {
        AndroidToolsSetupView(
            child: AndroidToolsPreviewFixtures.sdkPackage,
            model: AndroidToolsPreviewFixtures.model(.needsUpdate(installed: AndroidCLIVersion(components: [1, 0, 16_261_425])))
        )
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

    #Preview("Android tools: image used by a device") {
        AndroidToolsSetupView(child: AndroidToolsPreviewFixtures.sdkPackage,
                              model: AndroidToolsPreviewFixtures.model(.failed(
                                  AndroidSDKPackageRemovalError.usedByDevice("Pixel 9 Pro").localizedDescription
                              )))
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
