import CruftlessCore
import SwiftUI

/// The card that opens Review: what the plan frees, free space before and after, and the permanence warning.
/// No Detail screen shows a card like it, so Review never reads as another listing.
struct ReviewReceiptCard<Headline: View>: View {
    let reclaimableBytes: Int64
    /// Free space read when Review opened; nil hides the before and after line.
    let currentFreeBytes: Int64?
    let showsFreeSpace: Bool
    @ViewBuilder var headline: Headline

    private var irreversible: Color {
        DesignTokens.tierColor(for: .irreversible)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            headline

            if showsFreeSpace, let currentFreeBytes {
                FreeSpaceGainBar(freeBytes: currentFreeBytes, gainBytes: reclaimableBytes, gainTint: irreversible)

                HStack(alignment: .firstTextBaseline) {
                    Text("Free now \(ByteFormatter.format(currentFreeBytes))")
                    Spacer(minLength: 8)
                    Text("After ~\(ByteFormatter.format(currentFreeBytes + reclaimableBytes))")
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
            }

            Hairline()
                .padding(.top, 2)

            Text("This can't be undone. Files are deleted permanently, not moved to the Trash.")
                .font(.system(size: 11))
                .foregroundStyle(irreversible)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(irreversible.opacity(0.45), lineWidth: 1)
        }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("review.receipt")
    }
}

/// Free space after the plan, split into what is free now and what the plan adds.
private struct FreeSpaceGainBar: View {
    let freeBytes: Int64
    let gainBytes: Int64
    let gainTint: Color

    private var freeFraction: CGFloat {
        let after = max(freeBytes, 0) + max(gainBytes, 0)
        guard after > 0 else { return 1 }
        return CGFloat(max(freeBytes, 0)) / CGFloat(after)
    }

    var body: some View {
        GeometryReader { proxy in
            HStack(spacing: 0) {
                Rectangle()
                    .fill(.secondary)
                    .frame(width: proxy.size.width * freeFraction)
                Rectangle()
                    .fill(gainTint.opacity(0.55))
            }
        }
        .frame(height: 6)
        .clipShape(.capsule)
        .accessibilityHidden(true)
    }
}

#if DEBUG
    #Preview("Receipt: with free space") {
        ReviewReceiptCard(reclaimableBytes: 14_200_000_000, currentFreeBytes: 24_500_000_000, showsFreeSpace: true) {
            Text("14,2 GB").font(.system(size: 22, weight: .semibold))
        }
        .padding(16)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Receipt: capacity unknown") {
        ReviewReceiptCard(reclaimableBytes: 14_200_000_000, currentFreeBytes: nil, showsFreeSpace: true) {
            Text("14,2 GB").font(.system(size: 22, weight: .semibold))
        }
        .padding(16)
        .frame(width: PopoverMetrics.width)
    }
#endif
