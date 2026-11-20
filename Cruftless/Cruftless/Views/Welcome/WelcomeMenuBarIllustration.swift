import AppKit
import CruftlessCore
import SwiftUI

/// The top right of a Mac's screen: a pointer clicks the Cruftless icon in the menu bar and the popover opens under it.
struct WelcomeMenuBarIllustration: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var phase = DemoPhase.open
    @State private var isPressing = false
    @State private var isGlancing = false
    @State private var pointerGaze: CGSize?

    /// Where the demo pointer is and whether the popover is open.
    private enum DemoPhase {
        case away
        case onIcon
        case open
    }

    /// Where the sheep stands, and where its eyes are, in the illustration's own space.
    private enum Mascot {
        static let width: CGFloat = 92
        static let leading: CGFloat = 22
        static let bottom: CGFloat = 16
        static let eyes = CGPoint(x: 83, y: 166)
        static let towardMenuBarIcon = CGSize(width: 0.8, height: -0.9)
    }

    static let height: CGFloat = 236
    private static let menuBarHeight: CGFloat = 26
    private static let awayOffset = CGSize(width: -110, height: 150)

    private var isOpen: Bool {
        phase == .open || pointerGaze != nil
    }

    var body: some View {
        ZStack(alignment: .top) {
            menuBar
                .zIndex(1)
            MascotView(
                gaze: pointerGaze ?? (isGlancing ? Mascot.towardMenuBarIcon : .zero),
                isFollowingPointer: pointerGaze != nil
            )
            .frame(width: Mascot.width)
            .padding(.leading, Mascot.leading)
            .padding(.bottom, Mascot.bottom)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
        }
        .frame(maxWidth: .infinity)
        .frame(height: Self.height)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 14))
        .onContinuousHover(coordinateSpace: .local) { hover in
            switch hover {
            case let .active(point):
                pointerGaze = MascotView.gaze(from: Mascot.eyes, toward: point)
                isGlancing = false
            case .ended:
                pointerGaze = nil
            }
        }
        .task(id: reduceMotion) { await runDemo() }
        .accessibilityElement()
        .accessibilityLabel(
            """
            The Mac menu bar with the Cruftless icon clicked, and the Cruftless window open below it \
            listing Derived Data, simulators, archives and Gradle caches
            """
        )
    }

    /// Opens the popover, closes it, and clicks it open again, for as long as the step is on screen.
    /// It holds the popover open while the real pointer is over the illustration.
    private func runDemo() async {
        guard !reduceMotion else {
            phase = .open
            isGlancing = false
            return
        }
        while !Task.isCancelled {
            await pause(3.4)
            guard pointerGaze == nil else { continue }
            withAnimation(.easeInOut(duration: 0.7)) { phase = .away }
            await pause(1.3)
            guard pointerGaze == nil else {
                withAnimation(.easeOut(duration: 0.25)) { phase = .open }
                continue
            }
            isGlancing = true
            withAnimation(.easeInOut(duration: 0.9)) { phase = .onIcon }
            await pause(1.0)
            isPressing = true
            await pause(0.12)
            isPressing = false
            withAnimation(.spring(duration: 0.3, bounce: 0.25)) { phase = .open }
            await pause(1.4)
            isGlancing = false
        }
    }

    private func pause(_ seconds: Double) async {
        try? await Task.sleep(for: .seconds(seconds))
    }

    // MARK: Menu bar

    private var menuBar: some View {
        HStack(spacing: 15) {
            Spacer(minLength: 0)
            cruftlessItem
            systemItem("battery.75percent", size: 15)
            systemItem("wifi", size: 13)
            systemItem("switch.2", size: 12)
            Text("Fri 9:41")
                .font(.system(size: 12, weight: .medium))
        }
        .padding(.horizontal, 16)
        .frame(height: Self.menuBarHeight)
        .frame(maxWidth: .infinity)
        .background(.regularMaterial)
    }

    private func systemItem(_ symbol: String, size: CGFloat) -> some View {
        Image(systemName: symbol)
            .font(.system(size: size, weight: .medium))
    }

    private var cruftlessItem: some View {
        Image("MenuBarIcon")
            .renderingMode(.template)
            .resizable()
            .frame(width: 16, height: 16)
            .foregroundStyle(isOpen ? .white : .primary)
            .padding(.horizontal, 7)
            .padding(.vertical, 3)
            .background(Color.accentColor.opacity(isOpen ? 1 : 0), in: .rect(cornerRadius: 6))
            .scaleEffect(isPressing ? 0.92 : 1)
            .animation(.easeOut(duration: 0.12), value: isPressing)
            .overlay(alignment: .top) {
                popover
                    .fixedSize()
                    .offset(y: Self.menuBarHeight + 2)
                    .opacity(isOpen ? 1 : 0)
                    .scaleEffect(isOpen ? 1 : 0.96, anchor: .top)
            }
            .overlay(alignment: .topLeading) { demoPointer }
    }

    /// The system arrow, with its hot spot on the icon or resting below the menu bar.
    private var demoPointer: some View {
        let cursor = NSCursor.arrow
        let resting = CGSize(width: 14 - cursor.hotSpot.x, height: 12 - cursor.hotSpot.y)
        let offset = phase == .away
            ? CGSize(width: resting.width + Self.awayOffset.width, height: resting.height + Self.awayOffset.height)
            : resting
        return Image(nsImage: cursor.image)
            .scaleEffect(isPressing ? 0.85 : 1, anchor: .topLeading)
            .offset(offset)
            .opacity(pointerGaze == nil ? 1 : 0)
            .allowsHitTesting(false)
    }

    // MARK: Popover

    private var popover: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Cruftless")
                .font(.system(size: 13, weight: .semibold))
            WelcomeSketchBar(width: 196, height: 5, style: .init(Color.accentColor))
                .padding(.top, 8)
                .padding(.bottom, 6)
            WelcomeIllustrationRow(location: LocationCatalog.derivedData, sizeWidth: 34)
            WelcomeIllustrationRow(location: LocationCatalog.simulatorDevices, sizeWidth: 28)
            WelcomeIllustrationRow(location: LocationCatalog.simulatorRuntimes, sizeWidth: 34)
            WelcomeIllustrationRow(location: LocationCatalog.archives, sizeWidth: 24)
            WelcomeIllustrationRow(location: LocationCatalog.gradleCaches, sizeWidth: 30)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(width: 224, alignment: .leading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 14))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 6)
    }
}
