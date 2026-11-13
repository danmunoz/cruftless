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

    private var detailSummary: DetailSummary? {
        guard let contents, !contents.isUnavailable else { return nil }
        return DetailSummary(bytes: total, count: children.count, unit: .item)
    }

    private var offersClearAll: Bool {
        hasRows && !batchableChildren.isEmpty && location.tier.isDeletable && !location.mutationPolicy.isReadOnly
    }

    private var hasNotes: Bool {
        contents?.inventoryIssue != nil
            || !(contents?.androidSDKDiagnostics.isEmpty ?? true)
            || (location.platform == .android && !sourcePaths.isEmpty)
    }

    public var body: some View {
        LocationDetailScaffold(location: location, model: model, backTitle: backTitle, summary: detailSummary) {
            LoadStateView(
                isLoading: contents == nil,
                loadingTitle: "Reading \(location.title)…",
                error: contents?.failureReason,
                errorTitle: "Couldn't read \(location.title)",
                isEmpty: children.isEmpty && (contents?.androidSDKDiagnostics.isEmpty ?? true),
                emptySymbol: "folder",
                emptyTitle: "Nothing here",
                emptyMessage: "This location has no items Cruftless can list.",
                retry: { model.reloadDrillDown(for: location) },
                content: { content }
            )
        } footerTrailing: {
            if offersClearAll {
                clearAllFooter
            }
        }
    }

    private var content: some View {
        LazyVStack(spacing: 2) {
            if hasNotes {
                notes
            }

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

    /// Location-level notices that belong above the rows: inventory issues, SDK diagnostics, and Android root provenance.
    private var notes: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let issue = contents?.inventoryIssue {
                Label(issue, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }

            ForEach(contents?.androidSDKDiagnostics ?? []) { diagnostic in
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(diagnostic.category.rawValue) · \(diagnostic.reason.message)")
                        .font(.system(size: 10, weight: .medium))
                    Text(diagnostic.relativePath)
                        .font(.system(size: 10, design: .monospaced))
                        .textSelection(.enabled)
                    Text(
                        "source.properties: \(diagnostic.sourcePropertiesStatus.rawValue) · " +
                            "package.xml: \(diagnostic.packageXMLStatus.rawValue)"
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(7)
                .background(.orange.opacity(0.08), in: .rect(cornerRadius: 6))
            }

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
        let cacheRoots = location.id == LocationCatalog.gradleCaches.id ? location.resolveRoots() : []
        let isRiskEligibleGradleEntry = location.id == LocationCatalog.gradleCaches.id
            && GradleCacheEntryPolicy.isEligible(child, cacheRoots: cacheRoots)
        return PopoverRow(
            icon: nil,
            title: displayName(for: child),
            sizeBytes: child.reclaimableBytes,
            flagTint: child.isFlagged ? DesignTokens.tierColor(for: child.tier) : nil,
            action: rowAction(for: child, gradleCacheRoots: cacheRoots),
            isReadOnly: location.mutationPolicy == .readOnly && !isRiskEligibleGradleEntry && !isAndroidDevice(child)
        )
        .help(location.platform == .android ? child.url.path(percentEncoded: false) : child.name)
    }

    private func isAndroidDevice(_ child: ChildEntry) -> Bool {
        location.id == LocationCatalog.androidAVDs.id && child.id != "androidAVDs-unclassified"
    }

    private func rowAction(for child: ChildEntry, gradleCacheRoots: [URL]) -> RowAction? {
        if isAndroidDevice(child) {
            return RowAction("Delete Device", isDestructive: true) { model.requestAndroidAVDDeletion(child) }
        }
        if location.id == LocationCatalog.gradleCaches.id {
            guard GradleCacheEntryPolicy.isEligible(child, cacheRoots: gradleCacheRoots) else {
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

    private var clearAllFooter: some View {
        HStack(spacing: 10) {
            if batchableChildren.count < children.count {
                Text("Archives marked ⚠ are not included.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Clear All") {
                model.plan { context in
                    try DeletionPlanner.children(batchableChildren, in: location, context: context)
                }
            }
            .buttonStyle(.glass)
            .controlSize(.large)
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
