import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

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

    #Preview("Review: free space estimate") {
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
            currentFreeBytes: 24_500_000_000,
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
            progress: DeletionProgress(verb: .erase, targetName: "iPhone 17 Pro", phase: .mutating),
            onConfirm: {},
            onCancel: {}
        )
        .frame(width: PopoverMetrics.width)
        .frame(minHeight: PopoverMetrics.contentMinHeight, maxHeight: PopoverMetrics.height)
    }

    #Preview("Review: freeing space") {
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
            progress: DeletionProgress(verb: .erase, targetName: "iPhone 17 Pro", phase: .waitingForSpace),
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
