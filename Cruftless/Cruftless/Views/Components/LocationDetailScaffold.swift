import CruftlessCore
import SwiftUI

struct LocationDetailScaffold<Content: View>: View {
    let location: TrackedLocation
    let model: AppModel
    let backTitle: String
    let content: Content

    @State private var isInfoExpanded = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    init(
        location: TrackedLocation,
        model: AppModel,
        backTitle: String,
        @ViewBuilder content: () -> Content
    ) {
        self.location = location
        self.model = model
        self.backTitle = backTitle
        self.content = content()
    }

    #if DEBUG
        init(
            location: TrackedLocation,
            model: AppModel,
            previewInfoExpanded: Bool,
            @ViewBuilder content: () -> Content
        ) {
            self.location = location
            self.model = model
            backTitle = "Overview"
            self.content = content()
            _isInfoExpanded = State(initialValue: previewInfoExpanded)
        }
    #endif

    var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: location.title, backTitle: backTitle, onBack: model.pop) {
                HStack(spacing: 6) {
                    if location.hasDrillDown, location.id != LocationCatalog.androidAVDs.id {
                        SelectItemsButton(location: location, model: model)
                    }
                    infoButton
                }
            }
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

#if DEBUG
    #Preview("Section info: collapsed") {
        LocationDetailScaffold(location: LocationCatalog.derivedData, model: .previewPopulated(), backTitle: "Overview") {
            Text("Build files").padding()
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Section info: expanded archives") {
        LocationDetailScaffold(location: LocationCatalog.archives, model: .previewPopulated(), previewInfoExpanded: true) {
            PopoverPlaceholder(symbol: "archivebox", title: "Nothing here")
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Section info: expanded Gradle") {
        LocationDetailScaffold(location: LocationCatalog.gradleCaches, model: .previewPopulated(), previewInfoExpanded: true) {
            PopoverPlaceholder(symbol: "exclamationmark.triangle", title: "Couldn't read Gradle caches")
        }
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Section info: read-only") {
        LocationInfoPanel(location: LocationCatalog.androidStudioSystem)
            .padding(16)
            .frame(width: PopoverMetrics.width)
    }
#endif
