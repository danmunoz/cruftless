import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// Outcome of a completed plan.
public struct ResultView: View {
    public let result: DeletionResult
    public let freeSpaceDelta: FreeSpaceDelta?
    public let onDone: () -> Void

    @State private var contentHeight: CGFloat = 220
    @State private var footerHeight: CGFloat = 53

    public init(result: DeletionResult, freeSpaceDelta: FreeSpaceDelta? = nil, onDone: @escaping () -> Void) {
        self.result = result
        self.freeSpaceDelta = freeSpaceDelta
        self.onDone = onDone
    }

    public var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 16) {
                    headline
                    outcomes
                }
                .padding(.horizontal, PopoverMetrics.bandInset)
                .padding(.vertical, 20)
                .fixedSize(horizontal: false, vertical: true)
                .measuringHeight(into: $contentHeight)
            }
            .scrollBounceBehavior(.basedOnSize)

            PopoverFooter {
                Button("Done", action: onDone)
                    .buttonStyle(.glassProminent)
                    .controlSize(.large)
                    .keyboardShortcut(.defaultAction)
                    .frame(maxWidth: .infinity)
            }
            .measuringHeight(into: $footerHeight)
        }
        .preference(key: ContentHeightPreference.self, value: contentHeight + footerHeight)
    }

    /// True when anything in the batch was not a clean success: a real failure or an item the run never reached.
    private var hasIncompleteItems: Bool {
        result.hasFailures || result.notAttemptedCount > 0
    }

    private var headline: some View {
        VStack(spacing: 6) {
            Image(systemName: hasIncompleteItems ? "exclamationmark.triangle.fill" : "checkmark.circle.fill")
                .font(.system(size: 40))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(hasIncompleteItems ? .orange : .green)

            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteFormatter.format(result.totalFreedBytes))
                    .font(.system(size: 28, weight: .semibold))
                    .monospacedDigit()

                Text("freed")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            if let subLine {
                subLine
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var subLine: Text? {
        let freePart: Text? = freeSpaceDelta.map {
            Text("Free space \(ByteFormatter.format($0.before)) → \(ByteFormatter.format($0.after))")
        }

        // Distinct from a failure: these freed real bytes, which the headline above already counts.
        let partialPart: Text? = result.partiallyFailedCount > 0
            ? Text("^[\(result.partiallyFailedCount) item](inflect: true) partially removed")
            : nil

        let failedPart: Text? = result.failedCount > 0
            ? Text("^[\(result.failedCount) item](inflect: true) failed")
            : nil

        let notAttemptedPart: Text? = result.notAttemptedCount > 0
            ? Text("^[\(result.notAttemptedCount) item](inflect: true) not attempted")
            : nil

        return Self.joined([freePart, partialPart, failedPart, notAttemptedPart], separator: " · ")
    }

    private static func joined(_ parts: [Text?], separator: LocalizedStringKey) -> Text? {
        let parts = parts.compactMap { $0 }
        guard let first = parts.first else { return nil }
        return parts.dropFirst().reduce(first) { accumulated, part in
            Text("\(accumulated)\(Text(separator))\(part)")
        }
    }

    private var outcomesSummary: Text? {
        guard hasIncompleteItems else { return nil }

        let deletedPart = Text("^[\(result.succeededCount) item](inflect: true) deleted")
        let partialPart: Text? = result.partiallyFailedCount > 0
            ? Text("\(result.partiallyFailedCount) partially removed")
            : nil
        let failedPart: Text? = result.failedCount > 0 ? Text("\(result.failedCount) failed") : nil
        let notAttemptedPart: Text? = result.notAttemptedCount > 0
            ? Text("\(result.notAttemptedCount) not attempted")
            : nil

        return Self.joined([deletedPart, partialPart, failedPart, notAttemptedPart], separator: ", ")
    }

    private var outcomes: some View {
        VStack(alignment: .leading, spacing: 6) {
            if let outcomesSummary {
                outcomesSummary
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)
            }

            ForEach(result.items) { item in
                let glyph = outcomeGlyph(for: item.status)

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: glyph.symbol)
                        .font(.system(size: 12))
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(glyph.tint)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.target.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        if let reason = item.status.failureReason ?? item.status.notAttemptedReason {
                            Text(reason)
                                .font(.system(size: 11))
                                .foregroundStyle(glyph.tint)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    Spacer(minLength: 8)

                    Text(item.status.isSuccess || item.status.isPartialFailure ? ByteFormatter.format(item.freedBytes) : "-")
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 10))
            }
        }
    }

    private func outcomeGlyph(for status: ItemOutcomeStatus) -> (symbol: String, tint: Color) {
        if status.isSuccess {
            return ("checkmark.circle.fill", .green)
        }
        if status.isPartialFailure {
            return ("exclamationmark.triangle.fill", .orange)
        }
        if status.isNotAttempted {
            return ("minus.circle.fill", .secondary)
        }
        return ("xmark.circle.fill", .red)
    }
}

#if DEBUG
    private func previewOutcome(_ name: String, _ status: ItemOutcomeStatus, _ bytes: Int64) -> ItemOutcome {
        ItemOutcome(
            target: .simulatorErase(udid: name, name: name, isBooted: false, consequence: "", reclaimableBytes: bytes),
            status: status,
            freedBytes: status.isSuccess ? bytes : 0
        )
    }

    #Preview("Result: all succeeded") {
        ResultView(
            result: DeletionResult(items: [
                previewOutcome("ModuleCache.noindex", .succeeded, 3_200_000_000),
                previewOutcome("SuperApp-grkwqomdpx", .succeeded, 4_500_000_000)
            ]),
            freeSpaceDelta: FreeSpaceDelta(before: 2_500_000_000, after: 10_200_000_000),
            onDone: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Result: one item failed") {
        ResultView(
            result: DeletionResult(items: [
                previewOutcome("ModuleCache.noindex", .succeeded, 3_200_000_000),
                previewOutcome("SuperApp-grkwqomdpx", .failed(reason: "Changed since scan"), 4_500_000_000)
            ]),
            freeSpaceDelta: FreeSpaceDelta(before: 2_500_000_000, after: 5_700_000_000),
            onDone: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Result: item partially removed") {
        ResultView(
            result: DeletionResult(items: [
                previewOutcome("ModuleCache.noindex", .succeeded, 3_200_000_000),
                ItemOutcome(
                    target: .simulatorErase(
                        udid: "SuperApp-grkwqomdpx",
                        name: "SuperApp-grkwqomdpx",
                        isBooted: false,
                        consequence: "",
                        reclaimableBytes: 4_500_000_000
                    ),
                    status: .partiallyFailed(reason: "A file was in use and could not be removed"),
                    freedBytes: 2_100_000_000
                )
            ]),
            freeSpaceDelta: FreeSpaceDelta(before: 2_500_000_000, after: 7_800_000_000),
            onDone: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Result: all failed") {
        ResultView(
            result: DeletionResult(items: [
                previewOutcome("ModuleCache.noindex", .failed(reason: "Changed since scan"), 3_200_000_000),
                previewOutcome("SuperApp-grkwqomdpx", .failed(reason: "Path no longer exists"), 4_500_000_000)
            ]),
            freeSpaceDelta: FreeSpaceDelta(before: 2_500_000_000, after: 2_500_000_000),
            onDone: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    // A cancelled run: one item finished before the cancellation landed, the rest were never reached.
    #Preview("Result: cancelled") {
        ResultView(
            result: DeletionResult(items: [
                previewOutcome("ModuleCache.noindex", .succeeded, 3_200_000_000),
                previewOutcome("SuperApp-grkwqomdpx", .notAttempted(reason: .cancelled), 4_500_000_000),
                previewOutcome("iPhone 17 Pro 27.0", .notAttempted(reason: .cancelled), 900_000_000)
            ]),
            freeSpaceDelta: FreeSpaceDelta(before: 2_500_000_000, after: 5_700_000_000),
            onDone: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    // A second plan handed to a busy executor: refused outright, distinct copy from a cancelled run.
    #Preview("Result: executor busy") {
        ResultView(
            result: DeletionResult(items: [
                previewOutcome("ModuleCache.noindex", .notAttempted(reason: .executorBusy), 3_200_000_000)
            ]),
            freeSpaceDelta: nil,
            onDone: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }
#endif
