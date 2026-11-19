import SwiftUI

/// A sketch of the top right corner of the screen, with the Cruftless icon picked out in the menu bar and its popover below.
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
            .padding(.horizontal, 22)
            .frame(height: 30)
            .background(.regularMaterial)

            popoverSketch
                .padding(.trailing, 34)
        }
        .frame(maxWidth: .infinity, alignment: .topTrailing)
        .frame(height: 236, alignment: .top)
        .overlay(alignment: .bottomLeading) { nameplate }
        .background(.quaternary)
        .clipShape(.rect(cornerRadius: 14))
        .accessibilityElement()
        .accessibilityLabel("The Cruftless icon highlighted in the menu bar at the top right of the screen, with its window below")
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
