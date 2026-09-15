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
        onConfirm: @escaping () async -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.plan = plan
        self.backTitle = backTitle
        self.runningAppsWarning = runningAppsWarning
        self.isExecuting = isExecuting
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
        .disabled(isExecuting)
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
        }
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

                    Text(item.consequence)
                        .font(.system(size: 11))
                        .foregroundStyle(item.isFlagged ? DesignTokens.tierColor(for: .irreversible) : .secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                        Text(plan.confirmLabel).fontWeight(.semibold)
                    }
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
                .tint(.red)
            }
        }
    }
}

#if DEBUG
    /// A genuine flagged (⚠) `.path` target for previews.
    private func previewPathTarget(
        name: String,
        tier: Tier,
        consequence: String,
        reclaimableBytes: Int64
    ) -> DeletionTarget {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("CruftlessReviewPreview", isDirectory: true)
        let target = root.appendingPathComponent(name, isDirectory: true)
        try? FileManager.default.createDirectory(at: target, withIntermediateDirectories: true)

        guard
            let validatedPath = try? PathGuard(roots: [root]).validate(target),
            let fingerprint = Fingerprint.capture(at: target)
        else {
            return .simulatorDelete(
                udid: name,
                name: name,
                isBooted: false,
                consequence: consequence,
                reclaimableBytes: reclaimableBytes
            )
        }

        return .path(
            id: "preview-\(name)",
            name: name,
            validatedPath: validatedPath,
            fingerprint: fingerprint,
            tier: tier,
            consequence: consequence,
            reclaimableBytes: reclaimableBytes
        )
    }

    private func previewPlan(_ items: [DeletionTarget], confirmLabel: String = "Delete Permanently") -> DeletionPlan {
        .batch(items, confirmLabel: confirmLabel)
    }

    #Preview("Review: regular") {
        ReviewView(
            plan: previewPlan([
                previewPathTarget(
                    name: "SuperApp-eszycidpyopumzgdpamntyyawoix",
                    tier: .regen,
                    consequence: "Xcode rebuilds indexes and intermediates on the next build. "
                        + "The next build is slower.",
                    reclaimableBytes: 4_500_000_000
                )
            ]),
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Review: executing") {
        ReviewView(
            plan: previewPlan([
                previewPathTarget(
                    name: "SuperApp-eszycidpyopumzgdpamntyyawoix",
                    tier: .regen,
                    consequence: "Xcode rebuilds indexes and intermediates on the next build.",
                    reclaimableBytes: 4_500_000_000
                )
            ]),
            isExecuting: true,
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Review: flagged") {
        ReviewView(
            plan: .single(
                previewPathTarget(
                    name: "MyApp 1.4.2.xcarchive",
                    tier: .irreversible,
                    consequence: "Deletes the dSYMs and the archived app. Crash reports from these "
                        + "builds can never be symbolicated, and the build can't be re-exported.",
                    reclaimableBytes: 640_000_000
                )
            ),
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Review: Xcode running") {
        ReviewView(
            plan: previewPlan([
                previewPathTarget(
                    name: "SuperApp-eszycidpyopumzgdpamntyyawoix",
                    tier: .regen,
                    consequence: "Xcode rebuilds indexes and intermediates on the next build. "
                        + "The next build is slower.",
                    reclaimableBytes: 4_500_000_000
                )
            ]),
            runningAppsWarning: "Xcode is running. Anything it changes before deletion is skipped.",
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Review: mixed batch") {
        ReviewView(
            plan: previewPlan(
                [
                    previewPathTarget(
                        name: "SuperApp-eszycidpyopumzgdpamntyyawoix",
                        tier: .regen,
                        consequence: "Xcode rebuilds indexes and intermediates on the next build. "
                            + "The next build is slower.",
                        reclaimableBytes: 4_500_000_000
                    ),
                    previewPathTarget(
                        name: "ModuleCache.noindex",
                        tier: .regen,
                        consequence: "Xcode rebuilds cached Swift modules on the next build.",
                        reclaimableBytes: 3_200_000_000
                    ),
                    previewPathTarget(
                        name: "iPhone 17 Pro 27.0",
                        tier: .judgment,
                        consequence: "Xcode re-creates it the next time that device is connected.",
                        reclaimableBytes: 900_000_000
                    ),
                    .runtimeDelete(
                        identifier: "com.apple.CoreSimulator.SimRuntime.iOS-17-4",
                        name: "iOS 17.4",
                        consequence: "Xcode re-downloads this runtime the next time it's selected.",
                        reclaimableBytes: 7_800_000_000
                    )
                ],
                confirmLabel: "Delete Permanently"
            ),
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Review: booted simulator erase") {
        ReviewView(
            plan: .single(
                .simulatorErase(
                    udid: "U1",
                    name: "iPhone 17 Pro",
                    isBooted: true,
                    consequence: "Erases installed apps and their data on this simulator.",
                    reclaimableBytes: 4_500_000_000
                ),
                confirmLabel: "Shut Down and Erase"
            ),
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }
#endif
