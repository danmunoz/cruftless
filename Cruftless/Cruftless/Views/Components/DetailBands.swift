import CruftlessCore
import SwiftUI

/// What a Detail screen measured: its total and how many entries it lists, shown under the header title.
struct DetailSummary: Equatable {
    enum Unit {
        case item, device, runtime, folder
    }

    /// Nil when the location could not be measured.
    let bytes: Int64?
    /// Nil when there is nothing to count, and only the size shows.
    let count: Int?
    let unit: Unit

    var text: Text {
        let size = bytes.map { ByteFormatter.format($0) } ?? "—"
        guard let count else { return Text(size) }
        return switch unit {
        case .item: Text("\(size) · ^[\(count) item](inflect: true)")
        case .device: Text("\(size) · ^[\(count) device](inflect: true)")
        case .runtime: Text("\(size) · ^[\(count) runtime](inflect: true)")
        case .folder: Text("\(size) · ^[\(count) folder](inflect: true)")
        }
    }
}

/// The tinted band under every Detail header: the tier word and the first sentence of the location's consequence.
struct LocationTierStrip: View {
    let location: TrackedLocation

    var body: some View {
        let tierWord = Text(DesignTokens.tierWord(for: location.tier, locationId: location.id))
            .foregroundStyle(DesignTokens.tierColor(for: location.tier))
        let separator = Text(verbatim: "·").foregroundStyle(.tertiary)
        let consequence = Text(location.consequenceLead).foregroundStyle(.secondary)

        Text("\(tierWord) \(separator) \(consequence)")
            .font(.system(size: 11))
            .lineLimit(2)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, PopoverMetrics.bandInset)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.035))
            .accessibilityIdentifier("detail.tier-strip.\(location.id)")
    }
}

extension TrackedLocation {
    /// The consequence up to and including its first full stop.
    var consequenceLead: String {
        guard let periodIndex = consequence.firstIndex(of: ".") else { return consequence }
        return String(consequence[...periodIndex])
    }
}

#if DEBUG
    #Preview("Tier strip: every tier") {
        VStack(spacing: 0) {
            LocationTierStrip(location: LocationCatalog.deviceSupport)
            LocationTierStrip(location: LocationCatalog.simulatorDevices)
            LocationTierStrip(location: LocationCatalog.archives)
            LocationTierStrip(location: LocationCatalog.xcodeInstalls)
            LocationTierStrip(location: LocationCatalog.androidSDK)
        }
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Summary text: units and unmeasured") {
        VStack(alignment: .leading, spacing: 6) {
            DetailSummary(bytes: 14_200_000_000, count: 6, unit: .item).text
            DetailSummary(bytes: 21_600_000_000, count: 1, unit: .device).text
            DetailSummary(bytes: 25_300_000_000, count: 4, unit: .runtime).text
            DetailSummary(bytes: nil, count: 1, unit: .folder).text
        }
        .padding()
    }
#endif
