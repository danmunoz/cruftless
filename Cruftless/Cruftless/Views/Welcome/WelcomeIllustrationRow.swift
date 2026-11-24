import CruftlessCore
import SwiftUI

/// A compact, inert copy of a list row for the welcome illustrations: the location's real icon and name, a bar where its size goes.
struct WelcomeIllustrationRow: View {
    let location: TrackedLocation
    var sizeWidth: CGFloat = 30
    /// Replaces the size bar, for a row that is left out of the plan.
    var note: String?
    var showsFlag = false
    var isDimmed = false
    /// Replaces the size bar with a green check, for a row that has just been deleted.
    var isDone = false

    var body: some View {
        HStack(spacing: 8) {
            RowIconView(icon: location.icon)
                .scaleEffect(0.8)
                .frame(width: 16, height: 16)
            HStack(spacing: 5) {
                Text(location.title)
                    .font(.system(size: 12))
                    .lineLimit(1)
                if showsFlag {
                    RowFlagMarker(tint: DesignTokens.tierColor(for: location.tier))
                }
            }
            Spacer(minLength: 8)
            if isDone {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 13))
                    .foregroundStyle(.green)
                    .transition(.scale.combined(with: .opacity))
            } else if let note {
                Text(note)
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            } else {
                WelcomeSketchBar(width: sizeWidth, height: 6)
            }
        }
        .opacity(isDimmed ? 0.55 : 1)
        .frame(height: 24)
    }
}
