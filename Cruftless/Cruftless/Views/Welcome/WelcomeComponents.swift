import SwiftUI

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
        .padding(.top, 8)
    }
}

/// The inset shared by every row in a card and the label above it.
enum WelcomeCardMetrics {
    static let inset: CGFloat = 14
}

/// The menu bar glyph set into a sentence, lowered to sit on the text baseline.
enum WelcomeInlineGlyph {
    static var text: Text {
        Text(Image("MenuBarIcon").renderingMode(.template)).baselineOffset(-2)
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

/// The 11 pt label above a card, in line with the card's rows and closer to its own card than the one before.
struct WelcomeSectionLabel: View {
    let title: LocalizedStringKey

    init(_ title: LocalizedStringKey) {
        self.title = title
    }

    var body: some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.secondary)
            .padding(.leading, WelcomeCardMetrics.inset)
            .padding(.top, 6)
            .padding(.bottom, -4)
            .accessibilityAddTraits(.isHeader)
    }
}

/// A 30 pt rounded tile holding one symbol.
struct WelcomeSymbolTile: View {
    let symbol: String
    var tint: Color?

    var body: some View {
        Image(systemName: symbol)
            .font(.system(size: 14, weight: .medium))
            .foregroundStyle(tint.map(AnyShapeStyle.init) ?? AnyShapeStyle(.secondary))
            .frame(width: 30, height: 30)
            .background(.quaternary, in: .rect(cornerRadius: 9))
            .accessibilityHidden(true)
    }
}

/// A rounded bar standing in for a line of text in an illustration.
struct WelcomeSketchBar: View {
    let width: CGFloat
    var height: CGFloat = 7
    var style: AnyShapeStyle = .init(.tertiary)

    var body: some View {
        RoundedRectangle(cornerRadius: height / 2)
            .fill(style)
            .frame(width: width, height: height)
    }
}
