import AppKit
import CruftlessCore
import SwiftUI

/// A small copy of the Review screen beside the sheep. A pointer clicks Delete Permanently, Derived Data goes while the
/// sheep is sheared, and the flagged Archives row is never touched.
struct WelcomeReviewIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var stage = Stage.ready
    @State private var isPressing = false

    /// One beat of the demo.
    private enum Stage {
        case ready
        case aiming
        case deleting
        case done
    }

    private static let deletion: Duration = .seconds(2.4)
    private static let cardWidth: CGFloat = 296
    private static let awayOffset = CGSize(width: -110, height: -46)
    private static let afterClickOffset = CGSize(width: -76, height: 2)

    private var coat: WelcomeShearingSheep.Coat {
        switch stage {
        case .ready, .aiming: .overgrown
        case .deleting: .shearing
        case .done: .shorn
        }
    }

    private var isBusyOrDone: Bool {
        stage == .deleting || stage == .done
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            WelcomeShearingSheep(coat: coat)
                .animation(.easeInOut(duration: 0.35), value: coat)
            card
        }
        .padding(12)
        .frame(maxWidth: .infinity)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 14))
        .task(id: reduceMotion) { await runDemo() }
        .accessibilityElement()
        .accessibilityLabel(
            """
            The Review screen beside the sheep. Derived Data will be deleted and Archives is flagged and left out. \
            Clicking Delete Permanently deletes Derived Data and the sheep is sheared.
            """
        )
    }

    // MARK: Demo

    /// Aims, clicks, deletes and shows the result, then starts over, for as long as the step is on screen.
    private func runDemo() async {
        stage = .ready
        guard !reduceMotion else { return }
        while !Task.isCancelled {
            await pause(.seconds(1.4))
            withAnimation(.easeInOut(duration: 0.8)) { stage = .aiming }
            await pause(.seconds(1.1))
            isPressing = true
            await pause(.milliseconds(120))
            isPressing = false
            withAnimation(.easeInOut(duration: 0.6)) { stage = .deleting }
            await pause(Self.deletion)
            withAnimation(.snappy(duration: 0.3)) { stage = .done }
            await pause(.seconds(2.8))
            withAnimation(.easeInOut(duration: 0.5)) { stage = .ready }
        }
    }

    private func pause(_ duration: Duration) async {
        try? await Task.sleep(for: duration)
    }

    // MARK: Card

    private var card: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Review")
                    .font(.system(size: 13, weight: .semibold))
                Text("1 item")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            WelcomeIllustrationRow(
                location: LocationCatalog.derivedData,
                sizeWidth: stage == .deleting ? 0 : 34,
                isDone: stage == .done
            )
            .animation(stage == .deleting ? .linear(duration: 2.4) : .default, value: stage)
            WelcomeIllustrationRow(
                location: LocationCatalog.archives,
                note: "One at a time",
                showsFlag: true,
                isDimmed: true
            )

            Hairline()
                .padding(.vertical, 5)

            HStack(spacing: 10) {
                Button("Cancel") {}
                    .buttonStyle(.glass)
                    .opacity(isBusyOrDone ? 0.4 : 1)
                Spacer(minLength: 0)
                Button(role: .destructive) {} label: { deleteLabel }
                    .buttonStyle(.glassProminent)
                    .tint(.red)
                    .scaleEffect(isPressing ? 0.95 : 1)
                    .animation(.easeOut(duration: 0.1), value: isPressing)
                    .overlay(alignment: .topLeading) { demoPointer }
            }
            .font(.system(size: 12, weight: .semibold))
            .controlSize(.small)
            .focusable(false)
            .allowsHitTesting(false)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .frame(width: Self.cardWidth)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.14), radius: 8, y: 4)
    }

    /// Keeps the button's width while its label swaps for a spinner or a check.
    private var deleteLabel: some View {
        Text("Delete Permanently")
            .opacity(isBusyOrDone ? 0 : 1)
            .overlay {
                switch stage {
                case .deleting:
                    ProgressView()
                        .controlSize(.mini)
                        .tint(.white)
                case .done:
                    Image(systemName: "checkmark")
                        .fontWeight(.bold)
                case .ready, .aiming:
                    EmptyView()
                }
            }
    }

    /// The system arrow: over the rows, then on the button for the click, then just off it so the progress shows.
    private var demoPointer: some View {
        let cursor = NSCursor.arrow
        let onButton = CGSize(width: 60 - cursor.hotSpot.x, height: 12 - cursor.hotSpot.y)
        let shift: CGSize = switch stage {
        case .ready: Self.awayOffset
        case .aiming: .zero
        case .deleting, .done: Self.afterClickOffset
        }
        let offset = CGSize(width: onButton.width + shift.width, height: onButton.height + shift.height)
        return Image(nsImage: cursor.image)
            .scaleEffect(isPressing ? 0.85 : 1, anchor: .topLeading)
            .offset(offset)
            .opacity(reduceMotion ? 0 : 1)
            .allowsHitTesting(false)
    }
}
