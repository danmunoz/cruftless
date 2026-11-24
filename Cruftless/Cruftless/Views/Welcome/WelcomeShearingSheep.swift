import SwiftUI

/// The sheep beside the Review sketch: overgrown before the delete, mid-shear while it runs, shorn after.
struct WelcomeShearingSheep: View {
    enum Coat {
        case overgrown
        case shearing
        case shorn
    }

    let coat: Coat
    @Environment(\.colorScheme) private var colorScheme
    @State private var tuftsDrifted = false

    /// A clump of wool that leaves the fleece and drifts away, in the sheep's 120 pt frame.
    private struct Tuft {
        let start: CGPoint
        let end: CGPoint
        let size: CGFloat
    }

    private static let tufts = [
        Tuft(start: CGPoint(x: 28, y: 58), end: CGPoint(x: -6, y: 22), size: 13),
        Tuft(start: CGPoint(x: 20, y: 84), end: CGPoint(x: -14, y: 74), size: 10),
        Tuft(start: CGPoint(x: 44, y: 40), end: CGPoint(x: 26, y: 4), size: 9)
    ]

    var body: some View {
        ZStack(alignment: .topLeading) {
            frame("MascotShearOvergrown", shown: coat == .overgrown)
            frame("MascotShearMidway", shown: coat == .shearing)
            frame("MascotShearShorn", shown: coat == .shorn)
                .scaleEffect(coat == .shorn ? 1 : 0.96, anchor: .bottom)
            ForEach(Self.tufts.indices, id: \.self) { index in
                let tuft = Self.tufts[index]
                WoolTuft()
                    .frame(width: tuft.size, height: tuft.size)
                    .position(tuftsDrifted ? tuft.end : tuft.start)
                    .opacity(coat == .overgrown || tuftsDrifted ? 0 : 1)
            }
        }
        .frame(width: 120, height: 119)
        .shadow(color: colorScheme == .dark ? .white.opacity(0.7) : .clear, radius: 0.6)
        .onChange(of: coat) { _, newCoat in
            guard newCoat == .shearing else {
                if newCoat == .overgrown { tuftsDrifted = false }
                return
            }
            tuftsDrifted = false
            withAnimation(.easeOut(duration: 1.8)) { tuftsDrifted = true }
        }
        .accessibilityHidden(true)
    }

    private func frame(_ name: String, shown: Bool) -> some View {
        Image(name)
            .resizable()
            .scaledToFit()
            .opacity(shown ? 1 : 0)
    }
}

/// A loose clump of wool: three overlapping bumps in the mascot's cream and outline colours.
private struct WoolTuft: View {
    private static let wool = Color(red: 0xF8 / 255, green: 0xF0 / 255, blue: 0xE0 / 255)
    private static let outline = Color(red: 0x20 / 255, green: 0x10 / 255, blue: 0x28 / 255)

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / 2
            ZStack {
                bump(diameter: unit * 1.2, at: CGPoint(x: unit * 0.7, y: unit * 1.1))
                bump(diameter: unit * 1.3, at: CGPoint(x: unit * 1.2, y: unit * 0.8))
                bump(diameter: unit * 1.1, at: CGPoint(x: unit * 1.4, y: unit * 1.3))
            }
        }
    }

    private func bump(diameter: CGFloat, at center: CGPoint) -> some View {
        Circle()
            .fill(Self.wool)
            .overlay { Circle().strokeBorder(Self.outline, lineWidth: 1.2) }
            .frame(width: diameter, height: diameter)
            .position(center)
    }
}
