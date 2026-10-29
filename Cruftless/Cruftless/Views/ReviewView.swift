import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// The mandatory review step.
public struct ReviewView: View {
    public let plan: DeletionPlan
    public let backTitle: String
    public let runningAppsWarning: String?
    /// Whether the plan is being executed right now.
    public let isExecuting: Bool
    /// Current deletion progress.
    public let progress: DeletionProgress?
    /// Free space captured when Review opens.
    public let currentFreeBytes: Int64?
    public let notice: String?
    public let canConfirm: Bool
    public let isBusy: Bool
    public let showsActionLabels: Bool
    public let onConfirm: () async -> Void
    public let onCancel: () -> Void

    @State private var headerHeight: CGFloat = 44
    @State private var contentHeight: CGFloat = 140
    @State private var footerHeight: CGFloat = 53

    /// Total natural height of this screen, forwarded to `MainView`.
    private var naturalHeight: CGFloat {
        headerHeight + contentHeight + footerHeight
    }

    public init(
        plan: DeletionPlan,
        backTitle: String = "Overview",
        runningAppsWarning: String? = nil,
        isExecuting: Bool = false,
        progress: DeletionProgress? = nil,
        currentFreeBytes: Int64? = nil,
        notice: String? = nil,
        canConfirm: Bool = true,
        isBusy: Bool = false,
        showsActionLabels: Bool = false,
        onConfirm: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.plan = plan
        self.backTitle = backTitle
        self.runningAppsWarning = runningAppsWarning
        self.isExecuting = isExecuting
        self.progress = progress
        self.currentFreeBytes = currentFreeBytes
        self.notice = notice
        self.canConfirm = canConfirm
        self.isBusy = isBusy
        self.showsActionLabels = showsActionLabels
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(spacing: 0) {
            PopoverHeader(title: "Review", backTitle: backTitle, onBack: onCancel)
                .measuringHeight(into: $headerHeight)
            Hairline()

            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    summary

                    if let notice {
                        NoticeStrip(symbol: "hand.raised.fill", tint: .orange, text: notice)
                    }

                    if isExecuting {
                        executionStatus
                    }

                    if let runningAppsWarning {
                        NoticeStrip(
                            symbol: "info.circle.fill",
                            tint: .orange,
                            text: runningAppsWarning
                        )
                    }

                    items
                }
                .padding(.horizontal, PopoverMetrics.bandInset)
                .padding(.vertical, 14)
                .fixedSize(horizontal: false, vertical: true)
                .measuringHeight(into: $contentHeight)
            }
            .scrollBounceBehavior(.basedOnSize)

            footer
                .measuringHeight(into: $footerHeight)
        }
        .disabled(isExecuting || isBusy)
        .preference(key: ContentHeightPreference.self, value: naturalHeight)
    }

    private var summary: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(ByteFormatter.format(plan.totalReclaimableBytes))
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()

                Text("^[\(plan.count) item](inflect: true)")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }

            Text("This can't be undone. Files are deleted permanently, not moved to the Trash.")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            if let currentFreeBytes {
                Text(
                    "Free now \(ByteFormatter.format(currentFreeBytes)) · "
                        + "After ~\(ByteFormatter.format(currentFreeBytes + plan.totalReclaimableBytes))"
                )
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// Status text for the current deletion phase.
    private var executionStatus: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            ProgressView()
                .controlSize(.small)

            VStack(alignment: .leading, spacing: 2) {
                Text(progress?.label ?? plan.confirmLabel)
                    .font(.system(size: 12, weight: .medium))

                if let detail = progress?.phase.detail {
                    Text(detail)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 10))
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(plan.items) { item in
                VStack(alignment: .leading, spacing: 3) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.name)
                            .font(.system(size: 12, weight: .medium))
                            .lineLimit(1)
                            .truncationMode(.middle)

                        Spacer(minLength: 8)

                        Text(ByteFormatter.format(item.reclaimableBytes))
                            .font(.system(size: 12))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    if case let .androidAVDDelete(request) = item {
                        Text(request.identity.directory.path(percentEncoded: false))
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(item.consequence)
                        .font(.system(size: 11))
                        .foregroundStyle(item.isFlagged ? DesignTokens.tierColor(for: .irreversible) : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)

                    if showsActionLabels {
                        Text(actionLabel(for: item))
                            .font(.system(size: 11, weight: .semibold))
                    }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .glassEffect(in: .rect(cornerRadius: 10))
            }
        }
    }

    private var footer: some View {
        PopoverFooter {
            HStack(spacing: 10) {
                Button("Cancel", action: onCancel)
                    .buttonStyle(.glass)
                    .controlSize(.large)
                    .keyboardShortcut(.cancelAction)

                Spacer(minLength: 8)

                Button(role: .destructive) {
                    Task { await onConfirm() }
                } label: {
                    if isExecuting {
                        ProgressView().controlSize(.small)
                    } else {
                        Text(plan.confirmLabel)
                            .font(.system(size: showsActionLabels ? 12 : 13, weight: .semibold))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(showsActionLabels ? .regular : .large)
                .tint(.red)
                .disabled(!canConfirm)
            }
        }
    }

    private func actionLabel(for target: DeletionTarget) -> String {
        switch target {
        case let .path(_, _, _, _, tier, _, _, _): tier == .regen ? "Clear" : "Delete"
        case let .simulatorErase(_, _, booted, _, _): booted ? "Shut Down and Erase" : "Erase"
        case let .simulatorDelete(_, _, booted, _, _): booted ? "Shut Down and Delete" : "Delete"
        case .xctestSimulatorDelete: "Delete Test Simulator"
        case .runtimeDelete: "Delete Runtime"
        case .androidAVDDelete: "Delete Device"
        }
    }
}
