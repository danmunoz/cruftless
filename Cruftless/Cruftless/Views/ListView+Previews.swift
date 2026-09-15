import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

#if DEBUG
    #Preview("List: Populated") {
        ListView(model: .previewPopulated(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Xcode and Simulator running") {
        ListView(model: .previewWithXcodeAndSimulatorRunning(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Empty") {
        ListView(model: AppModel(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Scanning") {
        ListView(model: .previewScanning(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Rescanning one row") {
        ListView(model: .previewRescanning(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Rescanning a flagged row") {
        ListView(model: .previewRescanning(measuring: LocationCatalog.archives), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Scanning, before the plan lands") {
        ListView(model: .previewScanningWithoutPlan(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Restored from last session") {
        ListView(model: .previewRestored(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Paused in Low Power Mode") {
        ListView(model: .previewPausedInLowPowerMode(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Scan failed") {
        ListView(model: .previewFailed(), onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Preference issue") {
        let model = AppModel()
        model.inventory = Inventory(
            entries: PreviewFixtures.sampleEntries,
            capacity: PreviewFixtures.sampleCapacity,
            scannedAt: .now
        )
        model.preferenceIssues = [
            RootPreferenceIssue(
                preferenceKey: RootResolver.derivedDataPreferenceKey,
                value: "~/Library/Developer",
                reason: .protectedLocation
            )
        ]
        return ListView(model: model, onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }

    #Preview("List: Populated with unavailable row") {
        let model = AppModel()
        model.inventory = Inventory(
            entries: PreviewFixtures.sampleEntries + [
                .unavailable(location: LocationCatalog.toolchains, reason: "permission denied")
            ],
            capacity: PreviewFixtures.sampleCapacity,
            scannedAt: .now
        )
        return ListView(model: model, onOpenSettings: {})
            .frame(width: PopoverMetrics.width, height: PopoverMetrics.height)
    }
#endif
