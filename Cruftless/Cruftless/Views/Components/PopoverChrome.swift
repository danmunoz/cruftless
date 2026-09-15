import SwiftUI

/// Geometry for the menu bar popover, declared once.
public enum PopoverMetrics {
    public static let width: CGFloat = 380
    public static let height: CGFloat = 520
    public static let contentMinHeight: CGFloat = 240
    /// Header and footer band inset.
    public static let bandInset: CGFloat = 16
    public static let rowInset: CGFloat = 10
    public static let rowSpacing: CGFloat = 10
    public static let rowCornerRadius: CGFloat = 8
    public static let rowHeight: CGFloat = 38
    public static let iconSlot: CGFloat = 20
    public static let sizeColumn: CGFloat = 56
    public static let chevronColumn: CGFloat = 12
    public static let footerHeight: CGFloat = 36

    /// The pace of one navigation.
    public static let pushAnimation: Animation = .smooth(duration: 0.3)
}

/// Half-point rule separating the header and footer bands from the scrolling body.
struct Hairline: View {
    var body: some View {
        Rectangle()
            .fill(.separator)
            .frame(height: 0.5)
    }
}

/// The one back-and-title bar every pushed screen uses.
struct PopoverHeader<Trailing: View>: View {
    /// Side length of the circular back control.
    private static var controlSize: CGFloat {
        26
    }

    let title: String
    let backTitle: String
    let onBack: () -> Void
    @ViewBuilder var trailing: Trailing

    init(
        title: String,
        backTitle: String,
        onBack: @escaping () -> Void,
        @ViewBuilder trailing: () -> Trailing = { EmptyView() }
    ) {
        self.title = title
        self.backTitle = backTitle
        self.onBack = onBack
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: 8) {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 12, weight: .semibold))
                    .frame(width: Self.controlSize, height: Self.controlSize)
            }
            .buttonStyle(.glass)
            .clipShape(.circle)
            .help("Back to \(backTitle)")
            .accessibilityLabel("Back to \(backTitle)")

            Spacer(minLength: 8)

            Text(title)
                .font(.system(size: 13, weight: .semibold))
                .lineLimit(1)

            Spacer(minLength: 8)

            trailing
                .frame(minWidth: Self.controlSize, alignment: .trailing)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

/// Footer band holding a screen's terminal actions.
struct PopoverFooter<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        VStack(spacing: 0) {
            Hairline()
            content
                .padding(.horizontal, PopoverMetrics.bandInset)
                .padding(.vertical, 10)
        }
    }
}

struct PopoverPlaceholder<Actions: View>: View {
    let symbol: String
    let title: String
    let message: String?
    @ViewBuilder var actions: Actions

    init(
        symbol: String,
        title: String,
        message: String? = nil,
        @ViewBuilder actions: () -> Actions = { EmptyView() }
    ) {
        self.symbol = symbol
        self.title = title
        self.message = message
        self.actions = actions()
    }

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 30))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.tertiary)

            Text(title)
                .font(.system(size: 13, weight: .medium))

            if let message {
                Text(message)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 260)
            }

            actions
                .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, PopoverMetrics.bandInset)
    }
}

/// Group header inside a `Detail` screen.
struct PopoverSectionHeader: View {
    let title: String
    var subtitle: Text?

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)

            Spacer(minLength: 8)

            if let subtitle {
                subtitle
                    .font(.system(size: 11))
                    .foregroundStyle(.tertiary)
                    .monospacedDigit()
            }
        }
        .padding(.horizontal, PopoverMetrics.rowInset)
        .padding(.top, 10)
        .padding(.bottom, 2)
    }
}
