import AppKit
import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

public struct DetailView: View {
    public let location: TrackedLocation
    @Bindable public var model: AppModel
    public let backTitle: String

    /// What this screen was pushed with, held for as long as the slide lasts.
    @State private var pinned: DrillDownContent?

    public init(location: TrackedLocation, model: AppModel, backTitle: String = "Overview") {
        self.location = location
        self.model = model
        self.backTitle = backTitle
        _pinned = State(initialValue: model.drillDowns[location.id])
    }

    /// Pinned while navigating, live once the push has settled.
    private var contents: DrillDownContent? {
        model.isNavigating ? pinned : model.drillDowns[location.id]
    }

    private var children: [ChildEntry] {
        contents?.children ?? []
    }

    private var total: Int64 {
        children.reduce(0) { $0 + $1.reclaimableBytes }
    }

    private var sourcePaths: [String] {
        guard let entry = model.inventory?.entries.first(where: { $0.id == location.id }) else { return [] }
        return entry.roots.map { root in
            let path = root.url.path(percentEncoded: false)
            guard location.platform == .android else { return path }
            let provenance = [root.source, root.layout.map { "\($0), volume \(root.volumeIdentifier ?? "unknown")" }]
                .compactMap { $0 }
                .joined(separator: " · ")
            return "\(provenance.isEmpty ? "Android root" : provenance) · \(path)"
        }
    }

    private var batchableChildren: [ChildEntry] {
        children.filter { !$0.isFlagged }
    }

    private var hasRows: Bool {
        contents?.children.map { !$0.isEmpty } ?? false
    }

    public var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: location.title, backTitle: backTitle, onBack: model.pop)
            Hairline()

            LoadStateView(
                isLoading: contents == nil,
                loadingTitle: "Reading \(location.title)…",
                error: contents?.failureReason,
                errorTitle: "Couldn't read \(location.title)",
                isEmpty: children.isEmpty,
                emptySymbol: "folder",
                emptyTitle: "Nothing here",
                emptyMessage: "This location has no items Cruftless can list.",
                retry: { model.reloadDrillDown(for: location) },
                content: { content }
            )

            if hasRows, !batchableChildren.isEmpty, location.tier.isDeletable,
               !location.mutationPolicy.isReadOnly {
                footer
            }
        }
    }

    private var content: some View {
        ScrollView {
            LazyVStack(spacing: 2) {
                summary

                if let planFailure = model.planFailure {
                    NoticeStrip(symbol: "hand.raised.fill", tint: .red, text: planFailure)
                }

                ForEach(children) { child in
                    childRow(child)
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 8)
        }
        .scrollBounceBehavior(.basedOnSize)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteFormatter.format(total))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()

                Text("^[\(children.count) item](inflect: true)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let issue = contents?.inventoryIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Text(
                "\(tierWordText) \(Text(verbatim: "·").foregroundStyle(.tertiary)) \(consequenceText)"
            )
            .font(.system(size: 11))
            .lineLimit(2)

            if location.platform == .android {
                ForEach(sourcePaths, id: \.self) { path in
                    Text(path)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, PopoverMetrics.rowInset)
        .padding(.bottom, 6)
    }

    private func childRow(_ child: ChildEntry) -> some View {
        PopoverRow(
            icon: nil,
            title: displayName(for: child),
            sizeBytes: child.reclaimableBytes,
            flagTint: child.isFlagged ? DesignTokens.tierColor(for: child.tier) : nil,
            action: rowAction(for: child),
            isReadOnly: location.mutationPolicy == .readOnly
        )
        .help(location.platform == .android ? child.url.path(percentEncoded: false) : child.name)
    }

    private func rowAction(for child: ChildEntry) -> RowAction? {
        if location.id == LocationCatalog.gradleCaches.id {
            guard GradleCacheEntryPolicy.isEligible(child, cacheRoots: location.resolveRoots()) else {
                return nil
            }
            return RowAction("Clear") {
                model.openGradleCacheRiskWarning(for: child, in: location)
            }
        }
        guard !location.mutationPolicy.isReadOnly else { return nil }

        if location.tier == .reveal {
            return RowAction(DesignTokens.actionLabel(for: .reveal)) {
                NSWorkspace.shared.activateFileViewerSelecting([child.url])
            }
        } else {
            return RowAction(DesignTokens.actionLabel(for: child.tier), isDestructive: child.isFlagged) {
                model.plan { context in
                    try DeletionPlanner.child(child, in: location, context: context)
                }
            }
        }
    }

    private var footer: some View {
        PopoverFooter {
            HStack(spacing: 10) {
                if batchableChildren.count < children.count {
                    Text("Archives marked ⚠ are not included.")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Clear All") {
                    model.plan { context in
                        try DeletionPlanner.children(batchableChildren, in: location, context: context)
                    }
                }
                .buttonStyle(.glass)
                .controlSize(.large)
            }
        }
    }

    private func displayName(for child: ChildEntry) -> String {
        switch location.id {
        case LocationCatalog.deviceSupport.id:
            Naming.deviceSupportFolder(child.name)
        case LocationCatalog.derivedData.id:
            Naming.derivedDataFolder(child.name)
        default:
            child.name
        }
    }

    private var tierWordText: Text {
        Text(DesignTokens.tierWord(for: location.tier, locationId: location.id))
            .foregroundStyle(DesignTokens.tierColor(for: location.tier))
    }

    private var consequenceText: Text {
        Text(Self.firstSentence(of: location.consequence))
            .foregroundStyle(.secondary)
    }

    private static func firstSentence(of text: String) -> String {
        guard let periodIndex = text.firstIndex(of: ".") else { return text }
        return String(text[..<text.index(after: periodIndex)])
    }
}

#if DEBUG
    private extension ChildEntry {
        static let flaggedArchive = ChildEntry(
            id: "archive-1",
            name: "SuperApp 1.4 (12).xcarchive",
            url: URL(fileURLWithPath: "/Archives/SuperApp 1.4 (12).xcarchive"),
            reclaimableBytes: 1_100_000_000,
            staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -200, to: Date())),
            tier: .irreversible,
            consequence: LocationCatalog.archives.consequence
        )
    }

    #Preview("Detail: Derived Data (populated)") {
        DetailView(
            location: LocationCatalog.derivedData,
            model: .previewDrillDown(
                .children(PreviewFixtures.sampleChildren),
                for: LocationCatalog.derivedData.id
            )
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Detail: single item") {
        DetailView(
            location: LocationCatalog.derivedData,
            model: .previewDrillDown(
                .children(Array(PreviewFixtures.sampleChildren.prefix(1))),
                for: LocationCatalog.derivedData.id
            )
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Detail: Archives (flagged, batchable excluded)") {
        DetailView(
            location: LocationCatalog.archives,
            model: .previewDrillDown(
                .children([.flaggedArchive]),
                for: LocationCatalog.archives.id
            )
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Detail: empty") {
        DetailView(
            location: LocationCatalog.derivedData,
            model: .previewDrillDown(.children([]), for: LocationCatalog.derivedData.id)
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Detail: still reading") {
        DetailView(location: LocationCatalog.derivedData, model: .previewPopulated())
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("Detail: unreadable") {
        DetailView(
            location: LocationCatalog.derivedData,
            model: .previewDrillDownFailure(
                "Permission denied reading ~/Library/Developer/Xcode/DerivedData",
                for: LocationCatalog.derivedData.id
            )
        )
        .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
