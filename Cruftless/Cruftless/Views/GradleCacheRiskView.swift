import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// The per-attempt warning shown before planning a Gradle cache deletion.
public struct GradleCacheRiskView: View {
    public let location: TrackedLocation
    public let child: ChildEntry
    public let backTitle: String
    @Bindable public var model: AppModel

    public init(
        location: TrackedLocation,
        child: ChildEntry,
        model: AppModel,
        backTitle: String
    ) {
        self.location = location
        self.child = child
        self.model = model
        self.backTitle = backTitle
    }

    public var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: "Gradle cache warning", backTitle: backTitle, onBack: model.pop)
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    Label("Clear \(child.name)?", systemImage: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)

                    Text(
                        "Gradle may be using these files now, including from a background build. "
                            + "Removing them can interrupt builds, force large rebuilds or downloads, "
                            + "and make offline builds fail. Cruftless cannot verify that every Gradle "
                            + "process has stopped or guarantee that your projects will keep working."
                    )
                    .font(.system(size: 12))
                    .fixedSize(horizontal: false, vertical: true)

                    Text(child.url.path(percentEncoded: false))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)

                    Text("This choice applies to this entry and this attempt only. It is not saved.")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    if let planFailure = model.planFailure {
                        NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: planFailure)
                    }
                }
                .padding(.horizontal, PopoverMetrics.bandInset)
                .padding(.vertical, 16)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize)

            PopoverFooter {
                HStack(spacing: 10) {
                    Button("Cancel", action: model.pop)
                        .buttonStyle(.glass)
                        .controlSize(.large)
                        .keyboardShortcut(.cancelAction)

                    Spacer(minLength: 8)

                    Button("Accept Risk and Review") {
                        model.plan { context in
                            try DeletionPlanner.gradleCacheChildAfterRiskAcknowledgement(
                                child,
                                in: location,
                                context: context
                            )
                        }
                    }
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .tint(.red)
                }
            }
        }
    }
}

#if DEBUG
    #Preview("Gradle cache risk warning") {
        GradleCacheRiskView(
            location: LocationCatalog.gradleCaches,
            child: ChildEntry(
                id: "gradleCaches-/Users/example/.gradle/caches/modules-2",
                name: "modules-2",
                url: URL(fileURLWithPath: "/Users/example/.gradle/caches/modules-2", isDirectory: true),
                reclaimableBytes: 3_200_000_000,
                staleness: StalenessInfo(lastUsedDate: nil),
                tier: .info,
                consequence: LocationCatalog.gradleCaches.consequence
            ),
            model: .previewPopulated(),
            backTitle: LocationCatalog.gradleCaches.title
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
