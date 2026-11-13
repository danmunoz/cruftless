import SwiftUI

/// The header's rescan control at rest: the glyph alone, tinting to full contrast under the pointer.
struct RefreshGlyphButton: View {
    let action: () -> Void

    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 20, height: 20)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .animation(.snappy(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
        .help("Rescan tracked locations")
        .accessibilityLabel("Rescan")
    }
}

/// Quiet footer control that still reads as clickable, with its own hover and pressed states.
struct FooterButton: View {
    let title: String
    let action: () -> Void

    @State private var isHovered = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(isHovered ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background {
                    Capsule().fill(.quaternary.opacity(isHovered ? 1 : 0))
                }
                .contentShape(.capsule)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// Inline, non-blocking notice.
struct NoticeStrip: View {
    let symbol: String
    let tint: Color
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .font(.system(size: 11))
                .foregroundStyle(tint)

            Text(text)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, PopoverMetrics.rowInset)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: PopoverMetrics.rowCornerRadius, style: .continuous)
                .fill(tint.opacity(0.1))
        }
        .padding(.bottom, 4)
    }
}
