import CruftlessCore
import SwiftUI

/// Capacity strip plus its legend.
public struct CapacityBarView: View {
    public let capacity: VolumeCapacity
    public let reclaimableBytes: Int64

    public init(capacity: VolumeCapacity, reclaimableBytes: Int64) {
        self.capacity = capacity
        self.reclaimableBytes = reclaimableBytes
    }

    private var usedFill: Color {
        Color.primary.opacity(0.45)
    }

    private var freeFill: Color {
        Color.secondary.opacity(0.16)
    }

    private var total: Double {
        max(1, Double(capacity.totalBytes))
    }

    private func ratio(_ bytes: Int64) -> Double {
        min(1, max(0, Double(bytes) / total))
    }

    private var reclaimableRatio: Double {
        ratio(reclaimableBytes)
    }

    private var purgeableRatio: Double {
        ratio(capacity.purgeableBytes)
    }

    private var freeRatio: Double {
        ratio(capacity.freeBytes)
    }

    private var usedRatio: Double {
        max(0, 1 - reclaimableRatio - purgeableRatio - freeRatio)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            strip
            legend
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(
            "\(ByteFormatter.format(reclaimableBytes)) reclaimable of "
                + "\(ByteFormatter.format(capacity.totalBytes)) total. "
                + "Used \(ByteFormatter.format(capacity.usedBytes)), "
                + "purgeable \(ByteFormatter.format(capacity.purgeableBytes)), "
                + "free \(ByteFormatter.format(capacity.freeBytes))."
        )
    }

    private var strip: some View {
        GeometryReader { geometry in
            let width = geometry.size.width
            HStack(spacing: 1) {
                Rectangle().fill(usedFill)
                    .frame(width: max(2, width * usedRatio))
                Rectangle().fill(Color.accentColor)
                    .frame(width: max(2, width * reclaimableRatio))
                HatchedPurgeablePattern()
                    .frame(width: max(2, width * purgeableRatio))
                Rectangle().fill(freeFill)
                    .frame(width: max(2, width * freeRatio))
            }
            .clipShape(.capsule)
        }
        .frame(height: 4)
    }

    /// One line, three items.
    private var legend: some View {
        HStack(spacing: 0) {
            legendItem("Used", capacity.usedBytes) { swatch.fill(usedFill) }

            Spacer(minLength: 8)

            legendItem("Purgeable", capacity.purgeableBytes) {
                HatchedPurgeablePattern().clipShape(.rect(cornerRadius: 2))
            }

            Spacer(minLength: 8)

            legendItem("Free", capacity.freeBytes) {
                swatch.fill(freeFill)
                    .overlay { swatch.strokeBorder(Color.secondary.opacity(0.35), lineWidth: 0.5) }
            }
        }
        .font(.system(size: 11))
    }

    private var swatch: RoundedRectangle {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
    }

    private func legendItem(
        _ label: String,
        _ bytes: Int64,
        @ViewBuilder swatch: () -> some View
    ) -> some View {
        HStack(spacing: 5) {
            swatch()
                .frame(width: 6, height: 6)

            Text(label)
                .foregroundStyle(.secondary)

            Text(ByteFormatter.format(bytes))
                .fontWeight(.medium)
                .monospacedDigit()
        }
        .lineLimit(1)
        .fixedSize()
    }
}

#if DEBUG
    #Preview("Capacity") {
        CapacityBarView(
            capacity: VolumeCapacity(
                totalBytes: 500_000_000_000,
                freeBytes: 2_500_000_000,
                purgeableBytes: 14_200_000_000,
                usedBytes: 336_000_000_000
            ),
            reclaimableBytes: 107_300_000_000
        )
        .padding()
        .frame(width: PopoverMetrics.width)
    }
#endif
