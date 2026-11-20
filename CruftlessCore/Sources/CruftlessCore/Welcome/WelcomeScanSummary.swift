import Foundation

/// What the welcome window shows about the first scan: a total, a few rows, and what was left unmeasured.
public struct WelcomeScanSummary: Sendable, Hashable {
    public enum Phase: Sendable, Hashable {
        /// The scan has been asked for and has reported nothing yet.
        case starting
        case scanning
        case finished
        /// The scan ended without an inventory.
        case failed(String)
    }

    public enum RowDetail: Sendable, Hashable {
        case size(Int64)
        case measuring
        case waiting
        /// Why the row has no size, such as a protected area.
        case note(String)
    }

    public struct Row: Sendable, Hashable, Identifiable {
        public let id: String
        public let title: String
        public let detail: RowDetail
        public let isFlagged: Bool
    }

    /// The locations folded into one closing row.
    public struct Remainder: Sendable, Hashable {
        public let count: Int
        public let bytes: Int64
    }

    public let phase: Phase
    public let cleanableBytes: Int64
    public let completedCount: Int
    public let plannedCount: Int
    public let rows: [Row]
    public let remainder: Remainder?
    /// What a protected area kept from being measured, as one sentence.
    public let accessNote: String?
    /// The label of the control that opens the access list, when `accessNote` is set.
    public let accessActionTitle: String?

    public var isFinished: Bool {
        phase == .finished
    }

    /// The words after the total: "cleanable so far", "cleanable in 12 of 13 locations".
    public var totalCaption: String {
        guard isFinished else { return "cleanable so far" }
        let places = plannedCount == 1 ? "1 location" : "\(plannedCount) locations"
        return completedCount == plannedCount
            ? "cleanable in \(places)"
            : "cleanable in \(completedCount) of \(places)"
    }

    /// "4 of 13 locations" while the scan runs, `nil` otherwise.
    public var progressCaption: String? {
        guard phase == .scanning, plannedCount > 0 else { return nil }
        return "\(completedCount) of \(plannedCount) locations"
    }

    /// Builds the summary from the app's scan state; a finished inventory wins over a scan still reporting.
    public static func make(
        progress: ScanProgress,
        inventory: Inventory?,
        isScanning: Bool,
        failure: String?,
        rowLimit: Int = 5
    ) -> WelcomeScanSummary {
        if let inventory {
            return finished(inventory, rowLimit: rowLimit)
        }
        if isScanning {
            return scanning(progress, rowLimit: rowLimit)
        }
        return WelcomeScanSummary(
            phase: failure.map(Phase.failed) ?? .starting,
            cleanableBytes: 0,
            completedCount: 0,
            plannedCount: 0,
            rows: [],
            remainder: nil,
            accessNote: nil,
            accessActionTitle: nil
        )
    }

    private static func finished(_ inventory: Inventory, rowLimit: Int) -> WelcomeScanSummary {
        let entries = inventory.entries
        let needs = entries.compactMap(\.accessNeed)
        let limit = max(1, needs.isEmpty ? rowLimit : rowLimit - 1)
        let shown = entries.count > limit ? Array(entries.prefix(limit - 1)) : entries
        let folded = entries.dropFirst(shown.count)
        return WelcomeScanSummary(
            phase: .finished,
            cleanableBytes: inventory.cleanableBytes,
            completedCount: entries.count(where: { !$0.isUnavailable }),
            plannedCount: entries.count,
            rows: shown.map(row(for:)),
            remainder: folded.isEmpty
                ? nil
                : Remainder(count: folded.count, bytes: folded.reduce(0) { $0 + $1.reclaimableBytes }),
            accessNote: noteText(for: needs),
            accessActionTitle: needs.isEmpty ? nil : actionTitle(for: needs)
        )
    }

    private static func scanning(_ progress: ScanProgress, rowLimit: Int) -> WelcomeScanSummary {
        let landed = progress.rows
        let pending = progress.pending
        let measuring = progress.measuring
        let landedShown = min(landed.count, max(0, rowLimit - min(1, pending.count)))
        let pendingRows = pending
            .sorted { measuring.contains($0.id) && !measuring.contains($1.id) }
            .prefix(max(0, rowLimit - landedShown))
            .map { location in
                Row(
                    id: location.id,
                    title: location.title,
                    detail: measuring.contains(location.id) ? .measuring : .waiting,
                    isFlagged: location.tier.isFlagged
                )
            }
        return WelcomeScanSummary(
            phase: progress.hasPlan ? .scanning : .starting,
            cleanableBytes: progress.cleanableBytes,
            completedCount: progress.completedCount,
            plannedCount: progress.plannedCount,
            rows: landed.prefix(landedShown).map(row(for:)) + pendingRows,
            remainder: nil,
            accessNote: nil,
            accessActionTitle: nil
        )
    }

    private static func row(for entry: InventoryEntry) -> Row {
        let detail: RowDetail = if let need = entry.accessNeed, entry.isUnavailable {
            .note(need.summary)
        } else if entry.isUnavailable {
            .note("Unavailable")
        } else {
            .size(entry.reclaimableBytes)
        }
        return Row(id: entry.id, title: entry.location.title, detail: detail, isFlagged: entry.location.tier.isFlagged)
    }

    private static func noteText(for needs: [LocationAccessNeed]) -> String? {
        var seen: Set<String> = []
        let items = needs.flatMap(\.blocked).map(\.reason).filter { seen.insert($0).inserted }
        guard !items.isEmpty else { return nil }
        let names = ListFormatter.localizedString(byJoining: items)
        return "Not measured: \(names)."
    }

    /// Matches the action a blocked row carries in the list.
    private static func actionTitle(for needs: [LocationAccessNeed]) -> String {
        needs.allSatisfy(\.isNotAllowed) ? "Review Access" : "Allow Access"
    }
}
