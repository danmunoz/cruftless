import CruftlessCore
import SwiftUI

/// The first-run welcome window's identity and size.
public enum WelcomeWindow {
    public static let id = "welcome"
    static let width: CGFloat = 520
    /// The content height; the hidden title bar adds its own band above it.
    static let height: CGFloat = 480
    static let gutter: CGFloat = 40
    static let stepAnimation: Animation = .snappy(duration: 0.3)
}

/// The first-run welcome: where the app lives, the safety promise, what to scan, access, and the first scan.
public struct WelcomeView: View {
    public let model: WelcomeModel
    /// The same list Settings shows under Access.
    public let accessList: AccessListModel
    /// The app whose first scan the last step follows.
    public let app: AppModel
    @Environment(\.dismissWindow) private var dismissWindow
    @Environment(\.openSettings) private var openSettings
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isMovingForward = true

    public init(model: WelcomeModel, accessList: AccessListModel, app: AppModel) {
        self.model = model
        self.accessList = accessList
        self.app = app
    }

    public var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, WelcomeWindow.gutter)
                .padding(.top, 8)
                .id(model.step)
                .transition(stepTransition)
            footer
        }
        .frame(width: WelcomeWindow.width, height: WelcomeWindow.height)
        .clipped()
        .task { await model.prepare() }
        .onAppear { AppActivation.activate() }
        .onDisappear { model.finish() }
        .debugOpensSettings(model.settings)
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .location:
            WelcomeLocationStep()
        case .safety:
            WelcomeSafetyStep()
        case .setup:
            WelcomeSetupStep(settings: model.settings, detected: model.detected)
                .task(id: model.settings.platformSelection) { await model.refreshAccessNeeds() }
        case .access:
            WelcomeAccessStep(accessList: accessList)
        case .scan:
            WelcomeScanStep(summary: scanSummary, onOpenAccess: openAccessSettings)
        }
    }

    private var scanSummary: WelcomeScanSummary {
        WelcomeScanSummary.make(
            progress: app.scanProgress,
            inventory: app.inventory,
            isScanning: app.isScanning,
            failure: app.scanFailure
        )
    }

    /// A step slides in from the side it lies on; with Reduce Motion it fades.
    private var stepTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        return .asymmetric(
            insertion: .move(edge: isMovingForward ? .trailing : .leading).combined(with: .opacity),
            removal: .move(edge: isMovingForward ? .leading : .trailing).combined(with: .opacity)
        )
    }

    private var footer: WelcomeFooter {
        let goBack: (() -> Void)? = model.isFirstStep ? nil : { move(forward: false) { model.back() } }
        return WelcomeFooter(
            steps: model.steps,
            current: model.step,
            caption: model.step == .scan ? scanSummary.progressCaption : nil,
            primaryTitle: primaryTitle,
            isPrimaryProminent: model.step != .scan || scanSummary.isFinished,
            isPrimaryDisabled: !model.canAdvance,
            onBack: goBack,
            onPrimary: primaryAction
        )
    }

    private var primaryTitle: LocalizedStringKey {
        if model.step == .scan {
            return scanSummary.phase == .scanning || scanSummary.phase == .starting ? "Close" : "Done"
        }
        return model.startsScanNext ? "Start Scanning" : "Continue"
    }

    private func primaryAction() {
        if model.isLastStep {
            dismissWindow(id: WelcomeWindow.id)
        } else {
            move(forward: true) { model.advance() }
        }
    }

    /// Sets the direction first, so the outgoing step leaves by the matching edge.
    private func move(forward: Bool, _ change: () -> Void) {
        isMovingForward = forward
        withAnimation(WelcomeWindow.stepAnimation, change)
    }

    private func openAccessSettings() {
        app.requestAccessSettings()
        openSettings()
        AppActivation.activate()
    }
}

/// Step dots on the left, an optional caption, then Back and the primary action on the right.
struct WelcomeFooter: View {
    let steps: [WelcomeStep]
    let current: WelcomeStep
    var caption: String?
    let primaryTitle: LocalizedStringKey
    var isPrimaryProminent = true
    var isPrimaryDisabled = false
    let onBack: (() -> Void)?
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(steps) { step in
                    Capsule()
                        .fill(step == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: step == current ? 16 : 6, height: 6)
                }
            }
            .animation(WelcomeWindow.stepAnimation, value: current)
            .accessibilityElement()
            .accessibilityLabel(positionLabel)

            Spacer()

            if let caption {
                WelcomeCaption(caption)
                    .monospacedDigit()
            }
            if let onBack {
                Button("Back", action: onBack)
                    .buttonStyle(.glass)
            }
            primaryButton
                .keyboardShortcut(.defaultAction)
                .disabled(isPrimaryDisabled)
        }
        .controlSize(.large)
        .padding(.horizontal, WelcomeWindow.gutter)
        .padding(.top, 12)
        .padding(.bottom, 20)
    }

    @ViewBuilder private var primaryButton: some View {
        if isPrimaryProminent {
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.glassProminent)
        } else {
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.glass)
        }
    }

    private var positionLabel: String {
        let position = (steps.firstIndex(of: current) ?? 0) + 1
        return "Step \(position) of \(steps.count)"
    }
}
