import AppKit
import CruftlessCore
import SwiftUI

/// The first-run welcome window's identity and size.
public enum WelcomeWindow {
    public static let id = "welcome"
    static let width: CGFloat = 520
    /// The content height; the hidden title bar adds its own band above it.
    static let height: CGFloat = 460
    static let gutter: CGFloat = 40
}

/// The first-run welcome: where the app lives, the safety promise, access, and setup.
public struct WelcomeView: View {
    public let model: WelcomeModel
    /// The same list Settings shows under Access.
    public let accessList: AccessListModel
    @Environment(\.dismissWindow) private var dismissWindow

    public init(model: WelcomeModel, accessList: AccessListModel) {
        self.model = model
        self.accessList = accessList
    }

    public var body: some View {
        VStack(spacing: 0) {
            stepContent
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.horizontal, WelcomeWindow.gutter)
                .padding(.top, 8)
            footer
        }
        .frame(width: WelcomeWindow.width, height: WelcomeWindow.height)
        .task { await model.prepare() }
        .onAppear { NSApp.activate() }
        .onDisappear { model.finish() }
        .debugOpensSettings(model.settings)
    }

    @ViewBuilder private var stepContent: some View {
        switch model.step {
        case .location:
            WelcomeLocationStep()
        case .safety:
            WelcomeSafetyStep()
        case .access:
            WelcomeAccessStep(accessList: accessList)
        case .setup:
            WelcomeSetupStep(settings: model.settings, detected: model.detected)
        }
    }

    private var footer: WelcomeFooter {
        let goBack: (() -> Void)? = model.isFirstStep ? nil : { model.back() }
        let title: LocalizedStringKey = model.isLastStep ? "Start Scanning" : "Continue"
        return WelcomeFooter(
            steps: model.steps,
            current: model.step,
            primaryTitle: title,
            onBack: goBack,
            onPrimary: { primaryAction() }
        )
    }

    private func primaryAction() {
        if model.isLastStep {
            model.finish()
            dismissWindow(id: WelcomeWindow.id)
        } else {
            model.advance()
        }
    }
}

/// Step dots on the left, Back and the primary action on the right.
struct WelcomeFooter: View {
    let steps: [WelcomeStep]
    let current: WelcomeStep
    let primaryTitle: LocalizedStringKey
    let onBack: (() -> Void)?
    let onPrimary: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(steps) { step in
                    Circle()
                        .fill(step == current ? AnyShapeStyle(.primary) : AnyShapeStyle(.tertiary))
                        .frame(width: 6, height: 6)
                }
            }
            .accessibilityElement()
            .accessibilityLabel(positionLabel)

            Spacer()

            if let onBack {
                Button("Back", action: onBack)
                    .buttonStyle(.glass)
            }
            Button(primaryTitle, action: onPrimary)
                .buttonStyle(.glassProminent)
                .keyboardShortcut(.defaultAction)
        }
        .controlSize(.large)
        .padding(.horizontal, 20)
        .padding(.vertical, 16)
    }

    private var positionLabel: String {
        let position = (steps.firstIndex(of: current) ?? 0) + 1
        return "Step \(position) of \(steps.count)"
    }
}

/// A step's title and the sentence under it.
struct WelcomeHeading: View {
    let title: LocalizedStringKey
    let subtitle: Text?

    init(_ title: LocalizedStringKey, subtitle: Text? = nil) {
        self.title = title
        self.subtitle = subtitle
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 22, weight: .semibold))
                .fixedSize(horizontal: false, vertical: true)
            if let subtitle {
                subtitle
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A grouped box of rows.
struct WelcomeCard<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.separator, lineWidth: 0.5)
        }
    }
}

/// The 11 pt secondary line used under titles and at the foot of a step.
struct WelcomeCaption: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
