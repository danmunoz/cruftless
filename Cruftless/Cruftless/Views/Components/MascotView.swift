import SwiftUI

/// The sheep's expression.
enum MascotExpression: CaseIterable {
    case neutral
    case happy
    case worried

    var imageName: String {
        switch self {
        case .neutral: "MascotNeutral"
        case .happy: "MascotHappy"
        case .worried: "MascotWorried"
        }
    }
}

/// The sheep. Its body never moves; while neutral its eyes blink and follow `gaze`.
struct MascotView: View {
    var expression: MascotExpression = .neutral
    /// Where the eyes look, each axis from -1 to 1.
    var gaze: CGSize = .zero
    /// True while the gaze follows the pointer, which holds the blinking.
    var isFollowingPointer = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.colorScheme) private var colorScheme
    @State private var isBlinking = false

    var body: some View {
        ZStack(alignment: .bottom) {
            ForEach(MascotExpression.allCases, id: \.self) { candidate in
                Image(candidate.imageName)
                    .resizable()
                    .scaledToFit()
                    .overlay {
                        if candidate == .neutral {
                            MascotEyes(gaze: reduceMotion ? .zero : gaze, isClosed: isBlinking)
                        }
                    }
                    .opacity(candidate == expression ? 1 : 0)
            }
        }
        .shadow(color: colorScheme == .dark ? .white.opacity(0.7) : .clear, radius: 0.6)
        .animation(.easeOut(duration: 0.2), value: expression)
        .accessibilityHidden(true)
        .task(id: blinks) {
            guard blinks else {
                isBlinking = false
                return
            }
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(Double.random(in: 2.5 ... 5)))
                isBlinking = true
                try? await Task.sleep(for: .milliseconds(130))
                isBlinking = false
            }
        }
    }

    private var blinks: Bool {
        expression == .neutral && !reduceMotion && !isFollowingPointer
    }

    /// The gaze that looks from `eyes` toward `point`, at full reach from `distance` points away.
    static func gaze(from eyes: CGPoint, toward point: CGPoint, fullReachAt distance: CGFloat = 140) -> CGSize {
        let delta = CGSize(width: point.x - eyes.x, height: point.y - eyes.y)
        let length = hypot(delta.width, delta.height)
        guard length > 0 else { return .zero }
        let reach = min(1, length / distance)
        return CGSize(width: delta.width / length * reach, height: delta.height / length * reach)
    }
}

/// One eye of the neutral sheep, in the pixel grid of its trimmed source art.
private struct MascotEye: Identifiable {
    let id: Int
    let center: CGPoint
    let radii: CGSize
    let pupilCenter: CGPoint
    let pupilRadii: CGSize
    let highlightCenter: CGPoint
    let highlightRadius: CGFloat
    let lidRadii: CGSize
    let lashStart: CGPoint
    let lashControl: CGPoint
    let lashEnd: CGPoint

    static let artWidth: CGFloat = 314
    static let lashWidth: CGFloat = 4.9
    static let gazeReach = CGSize(width: 4.9, height: 6.6)
    static let outline = Color(red: 0.125, green: 0.063, blue: 0.157)
    static let face = Color(red: 0.267, green: 0.306, blue: 0.341)

    static let both = [
        MascotEye(
            id: 0,
            center: CGPoint(x: 170.1, y: 163.2),
            radii: CGSize(width: 17.7, height: 25.0),
            pupilCenter: CGPoint(x: 173.0, y: 166.4),
            pupilRadii: CGSize(width: 11.1, height: 16.4),
            highlightCenter: CGPoint(x: 168.9, y: 158.2),
            highlightRadius: 4.1,
            lidRadii: CGSize(width: 22.2, height: 28.7),
            lashStart: CGPoint(x: 155.0, y: 165.6),
            lashControl: CGPoint(x: 170.1, y: 176.3),
            lashEnd: CGPoint(x: 185.3, y: 165.6)
        ),
        MascotEye(
            id: 1,
            center: CGPoint(x: 249.4, y: 158.2),
            radii: CGSize(width: 12.3, height: 23.4),
            pupilCenter: CGPoint(x: 250.2, y: 161.5),
            pupilRadii: CGSize(width: 7.8, height: 14.8),
            highlightCenter: CGPoint(x: 247.7, y: 153.3),
            highlightRadius: 3.3,
            lidRadii: CGSize(width: 16.4, height: 27.1),
            lashStart: CGPoint(x: 239.5, y: 160.7),
            lashControl: CGPoint(x: 249.4, y: 169.7),
            lashEnd: CGPoint(x: 259.2, y: 160.7)
        )
    ]
}

/// Vector eyes drawn over the neutral sheep's painted ones.
private struct MascotEyes: View {
    let gaze: CGSize
    let isClosed: Bool

    var body: some View {
        GeometryReader { proxy in
            let unit = proxy.size.width / MascotEye.artWidth
            ForEach(MascotEye.both) { eye in
                if isClosed {
                    closed(eye, unit: unit)
                } else {
                    open(eye, unit: unit)
                }
            }
        }
        .animation(.easeOut(duration: 0.18), value: gaze)
    }

    private func open(_ eye: MascotEye, unit: CGFloat) -> some View {
        Ellipse()
            .fill(.white)
            .frame(width: eye.radii.width * 2 * unit, height: eye.radii.height * 2 * unit)
            .overlay {
                ZStack {
                    Ellipse()
                        .fill(MascotEye.outline)
                        .frame(width: eye.pupilRadii.width * 2 * unit, height: eye.pupilRadii.height * 2 * unit)
                        .offset(
                            x: (eye.pupilCenter.x - eye.center.x) * unit,
                            y: (eye.pupilCenter.y - eye.center.y) * unit
                        )
                    Circle()
                        .fill(.white)
                        .frame(width: eye.highlightRadius * 2 * unit)
                        .offset(
                            x: (eye.highlightCenter.x - eye.center.x) * unit,
                            y: (eye.highlightCenter.y - eye.center.y) * unit
                        )
                }
                .offset(
                    x: gaze.width * MascotEye.gazeReach.width * unit,
                    y: gaze.height * MascotEye.gazeReach.height * unit
                )
            }
            .clipShape(Ellipse())
            .position(x: eye.center.x * unit, y: eye.center.y * unit)
    }

    private func closed(_ eye: MascotEye, unit: CGFloat) -> some View {
        ZStack {
            Ellipse()
                .fill(MascotEye.face)
                .frame(width: eye.lidRadii.width * 2 * unit, height: eye.lidRadii.height * 2 * unit)
                .position(x: eye.center.x * unit, y: eye.center.y * unit)
            Path { path in
                path.move(to: CGPoint(x: eye.lashStart.x * unit, y: eye.lashStart.y * unit))
                path.addQuadCurve(
                    to: CGPoint(x: eye.lashEnd.x * unit, y: eye.lashEnd.y * unit),
                    control: CGPoint(x: eye.lashControl.x * unit, y: eye.lashControl.y * unit)
                )
            }
            .stroke(MascotEye.outline, style: StrokeStyle(lineWidth: MascotEye.lashWidth * unit, lineCap: .round))
        }
    }
}

#if DEBUG
    #Preview("Neutral, looking ahead") {
        MascotView()
            .frame(width: 160)
            .padding(40)
    }

    #Preview("Neutral, looking up and right") {
        MascotView(gaze: CGSize(width: 0.8, height: -0.9))
            .frame(width: 160)
            .padding(40)
    }

    #Preview("Eyes closed") {
        Image("MascotNeutral")
            .resizable()
            .scaledToFit()
            .overlay { MascotEyes(gaze: .zero, isClosed: true) }
            .frame(width: 160)
            .padding(40)
    }

    #Preview("Happy") {
        MascotView(expression: .happy)
            .frame(width: 160)
            .padding(40)
    }

    #Preview("Worried, dark") {
        MascotView(expression: .worried)
            .frame(width: 160)
            .padding(40)
            .preferredColorScheme(.dark)
    }
#endif
