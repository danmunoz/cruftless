#if DEBUG
    import CruftlessCore
    import CruftlessFixtures
    import Foundation

    /// Shared preview models.
    @MainActor
    extension AppModel {
        static func previewPopulated(scannedAt: Date = .now.addingTimeInterval(-360)) -> AppModel {
            let model = AppModel()
            model.inventory = Inventory(
                entries: PreviewFixtures.sampleEntries,
                capacity: PreviewFixtures.sampleCapacity,
                scannedAt: scannedAt
            )
            model.hasCompletedScanThisSession = true
            return model
        }

        static func previewDrillDown(
            _ contents: DrillDownContent,
            for locationId: String
        ) -> AppModel {
            let model = previewPopulated()
            model.drillDowns[locationId] = contents
            return model
        }

        static func previewDrillDownFailure(
            _ reason: String,
            for locationId: String
        ) -> AppModel {
            previewDrillDown(.unavailable(reason), for: locationId)
        }

        /// A first ever scan, part way through: three locations measured, the rest still pending, and the header total climbing.
        static func previewScanning() -> AppModel {
            let model = AppModel()
            model.activeScan = .user
            model.scanProgress = PreviewFixtures.partialScanProgress
            return model
        }

        static func previewRescanning(
            measuring location: TrackedLocation = LocationCatalog.derivedData
        ) -> AppModel {
            let model = previewPopulated()
            model.activeScan = .user
            model.scanProgress = PreviewFixtures.rescanProgress(measuring: location)
            return model
        }

        /// The frame before the scan has said what it will cover: no checklist yet, just "Scanning…".
        static func previewScanningWithoutPlan() -> AppModel {
            let model = AppModel()
            model.activeScan = .user
            return model
        }

        static func previewRestored(scannedAt: Date = .now.addingTimeInterval(-7_200)) -> AppModel {
            let model = previewPopulated(scannedAt: scannedAt)
            // No scan has run this session, which is what makes the rows restored (`AppModel.isInventoryRestored`).
            model.hasCompletedScanThisSession = false
            return model
        }

        /// Restored rows with the automatic scan paused, and the refusal an action on one of those rows produces.
        static func previewPausedInLowPowerMode() -> AppModel {
            let model = previewRestored()
            model.isAutomaticScanPaused = true
            model.planFailure = "These sizes are from 2 hours ago. Measuring now: try again in a moment."
            return model
        }

        static func previewFailed(
            _ reason: String = "permission denied",
            locationId: String = LocationCatalog.derivedData.id
        ) -> AppModel {
            let model = AppModel()
            model.setScanFailure(reason, for: locationId)
            return model
        }

        static func previewWithXcodeRunning() -> AppModel {
            let model = previewPopulated()
            model.runningApps = .xcode
            return model
        }

        static func previewWithXcodeAndSimulatorRunning() -> AppModel {
            let model = previewPopulated()
            model.runningApps = .both
            return model
        }
    }
#endif
