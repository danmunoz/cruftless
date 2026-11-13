import CruftlessCore
import SwiftUI

/// The frame every Detail screen shares: a header carrying the measured total, the tier strip, a scrolling body, and a
/// footer band with Select Items on the left and the screen's own location action on the right.
struct LocationDetailScaffold<Content: View, FooterTrailing: View>: View {
    let location: TrackedLocation
    let model: AppModel
    let backTitle: String
    let summary: DetailSummary?
    let content: Content
    let footerTrailing: FooterTrailing

    @State private var isInfoExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        location: TrackedLocation,
        model: AppModel,
        backTitle: String,
        summary: DetailSummary?,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footerTrailing: () -> FooterTrailing
    ) {
        self.location = location
        self.model = model
        self.backTitle = backTitle
        self.summary = summary
        self.content = content()
        self.footerTrailing = footerTrailing()
    }

    #if DEBUG
        init(
            location: TrackedLocation,
            model: AppModel,
            summary: DetailSummary? = nil,
            previewInfoExpanded: Bool,
            @ViewBuilder content: () -> Content,
            @ViewBuilder footerTrailing: () -> FooterTrailing
        ) {
            self.init(
                location: location,
                model: model,
                backTitle: "Overview",
                summary: summary,
                content: content,
                footerTrailing: footerTrailing
            )
            _isInfoExpanded = State(initialValue: previewInfoExpanded)
        }
    #endif

    /// Every location with a child listing offers Select Items, except Android Virtual Devices.
    private var offersSelection: Bool {
        location.hasDrillDown && location.id != LocationCatalog.androidAVDs.id
    }

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: location.title, subtitle: summary?.text, backTitle: backTitle, onBack: model.pop) {
                infoButton
            }
            Hairline()
            LocationTierStrip(location: location)
            Hairline()

            GeometryReader { geometry in
                ScrollView {
                    VStack(spacing: 0) {
                        if isInfoExpanded {
                            LocationInfoPanel(location: location)
                                .padding(.horizontal, PopoverMetrics.bandInset)
                                .padding(.top, 12)
                                .padding(.bottom, 8)
                        }
                        content
                    }
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .top)
                }
                .scrollBounceBehavior(.basedOnSize)
            }

            PopoverFooter {
                HStack(spacing: 10) {
                    if offersSelection {
                        SelectItemsButton(location: location, model: model)
                    }
                    Spacer(minLength: 0)
                    footerTrailing
                }
                .frame(minHeight: PopoverMetrics.footerControlHeight)
            }
        }
    }

    private var infoButton: some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
                isInfoExpanded.toggle()
            }
        } label: {
            Image(systemName: isInfoExpanded ? "info.circle.fill" : "info.circle")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(isInfoExpanded ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
                .frame(width: 26, height: 26)
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(isInfoExpanded ? "Hide section information" : "Show section information")
        .accessibilityLabel("About \(location.title)")
        .accessibilityValue(isInfoExpanded ? "Expanded" : "Collapsed")
        .accessibilityHint("Shows or hides the explanation and deletion risks.")
        .accessibilityIdentifier("section-info.toggle.\(location.id)")
    }
}

struct LocationInfoPanel: View {
    let location: TrackedLocation

    var body: some View {
        let explanation = LocationExplanation.explanation(for: location)
        VStack(alignment: .leading, spacing: 10) {
            Text("About this section")
                .font(.callout.weight(.semibold))

            VStack(alignment: .leading, spacing: 3) {
                Text("What it is")
                    .font(.caption.weight(.semibold))
                Text(explanation.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text("Deletion risk")
                    .font(.caption.weight(.semibold))
                Text(explanation.risk)
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            Text("Deletion is permanent. Files are not moved to the Trash.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .fixedSize(horizontal: false, vertical: true)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.quaternary.opacity(0.4), in: .rect(cornerRadius: 8))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("section-info.panel.\(location.id)")
    }
}

extension LocationDetailScaffold where FooterTrailing == EmptyView {
    init(
        location: TrackedLocation,
        model: AppModel,
        backTitle: String,
        summary: DetailSummary?,
        @ViewBuilder content: () -> Content
    ) {
        self.init(
            location: location,
            model: model,
            backTitle: backTitle,
            summary: summary,
            content: content,
            footerTrailing: { EmptyView() }
        )
    }
}

#if DEBUG
    #Preview("Scaffold: collapsed info, Clear All") {
        LocationDetailScaffold(
            location: LocationCatalog.derivedData,
            model: .previewPopulated(),
            backTitle: "Overview",
            summary: DetailSummary(bytes: 18_400_000_000, count: 12, unit: .item)
        ) {
            Text("Build files").padding()
        } footerTrailing: {
            Button("Clear All") {}
                .buttonStyle(.glass)
                .controlSize(.large)
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Scaffold: expanded archives, no summary yet") {
        LocationDetailScaffold(location: LocationCatalog.archives, model: .previewPopulated(), previewInfoExpanded: true) {
            PopoverPlaceholder(symbol: "archivebox", title: "Nothing here")
        } footerTrailing: {
            EmptyView()
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Scaffold: expanded Gradle error") {
        LocationDetailScaffold(location: LocationCatalog.gradleCaches, model: .previewPopulated(), previewInfoExpanded: true) {
            PopoverPlaceholder(symbol: "exclamationmark.triangle", title: "Couldn't read Gradle caches")
        } footerTrailing: {
            EmptyView()
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Section info: read-only") {
        LocationInfoPanel(location: LocationCatalog.androidStudioSystem)
            .padding(16)
            .frame(width: PopoverMetrics.width)
    }
#endif
