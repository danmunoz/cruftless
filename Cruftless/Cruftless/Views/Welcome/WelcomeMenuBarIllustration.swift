import SwiftUI

/// A sketch of the top right corner of the screen, with the Cruftless icon picked out in the menu bar.
struct WelcomeMenuBarIllustration: View {
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
                otherItem
                otherItem
            }
            .padding(.horizontal, 20)
            .frame(height: 30)
            .background(.regularMaterial)

            popoverSketch
                .padding(.trailing, 44)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(height: 150, alignment: .top)
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement()
        .accessibilityLabel("The Cruftless icon highlighted in the menu bar at the top right of the screen")
    }

    private var otherItem: some View {
        RoundedRectangle(cornerRadius: 4)
            .fill(.tertiary)
            .frame(width: 16, height: 16)
    }

    private var popoverSketch: some View {
        VStack(alignment: .leading, spacing: 9) {
            bar(width: 70, height: 12, style: AnyShapeStyle(.primary))
            bar(width: 160, height: 4, style: AnyShapeStyle(Color.accentColor))
            bar(width: 138, height: 7, style: AnyShapeStyle(.tertiary))
            bar(width: 112, height: 7, style: AnyShapeStyle(.tertiary))
            bar(width: 126, height: 7, style: AnyShapeStyle(.tertiary))
        }
        .padding(14)
        .frame(width: 190, height: 130, alignment: .topLeading)
        .background(Color(nsColor: .controlBackgroundColor), in: .rect(cornerRadius: 12))
        .shadow(color: .black.opacity(0.18), radius: 12, y: 6)
    }

    private func bar(width: CGFloat, height: CGFloat, style: AnyShapeStyle) -> some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(style)
            .frame(width: width, height: height)
    }
}
