import SwiftUI

/// A sketch of the top right corner of the screen, with the Cruftless icon picked out in the menu bar and its popover below.
struct WelcomeMenuBarIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isGlancing = false
    @State private var pointerGaze: CGSize?

    /// Where the sheep stands, and where its eyes are, in the illustration's own space.
    private enum Mascot {
        static let width: CGFloat = 92
        static let leading: CGFloat = 22
        static let bottom: CGFloat = 64
        static let eyes = CGPoint(x: 83, y: 118)
        static let towardMenuBarIcon = CGSize(width: 0.8, height: -0.9)
    }

    var body: some View {
        VStack(alignment: .trailing, spacing: 10) {
            HStack(spacing: 16) {
                Spacer(minLength: 0)
                otherItem
                Image("MenuBarIcon")
                    .renderingMode(.template)
                    .resizable()
                    .frame(width: 16, height: 16)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .background(Color.accentColor, in: .rect(cornerRadius: 6))
                    .scaleEffect(isGlancing ? 1.15 : 1)
                    .animation(.spring(duration: 0.35, bounce: 0.4), value: isGlancing)
                otherItem
                otherItem
            }
            .padding(.horizontal, 22)
            .frame(height: 30)
            .background(.regularMaterial)

            popoverSketch
                .padding(.trailing, 34)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(height: 236, alignment: .top)
        .overlay(alignment: .bottomLeading) { nameplate }
        .overlay(alignment: .bottomLeading) {
            MascotView(
                gaze: pointerGaze ?? (isGlancing ? Mascot.towardMenuBarIcon : .zero),
                isFollowingPointer: pointerGaze != nil
            )
                .frame(width: Mascot.width)
                .padding(.leading, Mascot.leading)
                .padding(.bottom, Mascot.bottom)
        }
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 14))
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case let .active(point):
                pointerGaze = MascotView.gaze(from: Mascot.eyes, toward: point)
                isGlancing = false
            case .ended:
                pointerGaze = nil
            }
        }
        .task(id: reduceMotion) { await glanceAtMenuBarIcon() }
        .accessibilityElement()
        .accessibilityLabel("The Cruftless icon highlighted in the menu bar at the top right of the screen, with its window below")
    }

    /// Now and then the sheep looks up at the menu bar icon, which answers with a small bounce.
    /// It never does while its eyes follow the pointer.
    private func glanceAtMenuBarIcon() async {
        guard !reduceMotion else {
            isGlancing = false
            return
        }
        while !Task.isCancelled {
            try? await Task.sleep(for: .seconds(4))
            guard pointerGaze == nil else { continue }
            isGlancing = true
            try? await Task.sleep(for: .seconds(1.8))
            isGlancing = false
        }
    }

    private var nameplate: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text("Cruftless")
                .font(.system(size: 15, weight: .semibold))
            Text("Xcode and Android cleanup")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
        .padding(.leading, 24)
        .padding(.bottom, 20)
    }

    private var otherItem: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.tertiary)
            .frame(width: 16, height: 16)
    }

    private var popoverSketch: some View {
        VStack(alignment: .leading, spacing: 11) {
            WelcomeSketchBar(width: 92, height: 16, style: .init(.primary))
            WelcomeSketchBar(width: 182, height: 5, style: .init(Color.accentColor))
            sketchRow(96, 34)
                .padding(.top, 4)
            sketchRow(74, 28)
            sketchRow(108, 34)
            sketchRow(82, 24)
            sketchRow(90, 30)
        }
        .padding(16)
        .frame(width: 214, height: 230, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    private func sketchRow(_ name: CGFloat, _ size: CGFloat) -> some View {
        HStack(spacing: 0) {
            WelcomeSketchBar(width: name)
            Spacer(minLength: 0)
            WelcomeSketchBar(width: size)
        }
    }
}
