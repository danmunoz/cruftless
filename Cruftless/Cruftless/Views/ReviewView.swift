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
    /// Per-item state while the plan executes.
    public let run: DeletionRunState?
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
    @State private var userScrolled = false

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
        run: DeletionRunState? = nil,
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
        self.run = run
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
                .disabled(isExecuting)
            Hairline()

            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 14) {
                        summary

                        if let notice {
                            NoticeStrip(symbol: "hand.raised.fill", tint: .orange, text: notice)
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
                .onScrollPhaseChange { _, phase in
                    if phase == .interacting, isExecuting { userScrolled = true }
                }
                .onChange(of: isExecuting) { _, executing in
                    if executing { userScrolled = false }
                }
                .onChange(of: run?.activeID) { _, activeID in
                    guard let activeID, !userScrolled else { return }
                    withAnimation(.easeInOut(duration: 0.25)) { proxy.scrollTo(activeID, anchor: .center) }
                }
            }

            footer
                .measuringHeight(into: $footerHeight)
                .disabled(isExecuting)
        }
        .disabled(isBusy)
        .preference(key: ContentHeightPreference.self, value: naturalHeight)
    }

    private var summary: some View {
        ReviewReceiptCard(
            reclaimableBytes: plan.totalReclaimableBytes,
            currentFreeBytes: currentFreeBytes,
            showsFreeSpace: !isExecuting
        ) {
            if isExecuting, let run {
                executionHeader(run)
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    Text(ByteFormatter.format(plan.totalReclaimableBytes))
                        .font(.system(size: 22, weight: .semibold))
                        .monospacedDigit()

                    Text("^[\(plan.count) item](inflect: true)")
                        .font(.system(size: 13))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    /// Overall position and a determinate bar while the plan executes.
    private func executionHeader(_ run: DeletionRunState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text("Deleting \(run.currentPosition) of \(run.total)")
                    .font(.system(size: 22, weight: .semibold))
                    .monospacedDigit()
                Text("\(ByteFormatter.format(plan.totalReclaimableBytes)) in total")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: Double(run.finishedCount), total: Double(max(run.total, 1)))
                .progressViewStyle(.linear)
                .tint(.red)
                .animation(.snappy, value: run.finishedCount)
        }
    }

    private func runState(for item: DeletionTarget) -> DeletionItemRunState? {
        guard isExecuting || run?.finishedCount ?? 0 > 0 else { return nil }
        return run?.state(for: item.id)
    }

    private var items: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(plan.items) { item in
                ReviewItemRow(
                    item: item,
                    state: runState(for: item),
                    phaseDetail: progress?.phase.detail,
                    showsActionLabel: showsActionLabels
                )
                .id(item.id)

                if item.id != plan.items.last?.id {
                    Hairline()
                }
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
                .disabled(!canConfirm || isExecuting)
            }
        }
    }
}
