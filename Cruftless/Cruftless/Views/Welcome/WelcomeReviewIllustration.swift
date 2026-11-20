import CruftlessCore
import SwiftUI

/// A small copy of the Review screen: one location going, a flagged one left out, and the button that deletes.
struct WelcomeReviewIllustration: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Review")
                    .font(.system(size: 13, weight: .semibold))
                Text("1 item")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
            .padding(.bottom, 2)

            WelcomeIllustrationRow(location: LocationCatalog.derivedData, sizeWidth: 34)
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
                Spacer(minLength: 0)
                Button("Delete Permanently", role: .destructive) {}
                    .buttonStyle(.glassProminent)
                    .tint(.red)
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
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(.quaternary, in: .rect(cornerRadius: 14))
        .accessibilityElement()
        .accessibilityLabel(
            "The Review screen: Derived Data will be deleted, Archives is flagged and left out, with Cancel and Delete Permanently buttons"
        )
    }

    private static let cardWidth: CGFloat = 360
}
