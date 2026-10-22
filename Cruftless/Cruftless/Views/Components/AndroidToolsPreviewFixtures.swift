#if DEBUG
    import CruftlessCore
    import Foundation

    @MainActor
    enum AndroidToolsPreviewFixtures {
        static let device = ChildEntry(
            id: "androidAVDs-Pixel_9_Pro", name: "Pixel 9 Pro",
            url: URL(fileURLWithPath: "/Users/example/.android/avd/Pixel_9_Pro.avd"),
            reclaimableBytes: 8_000_000_000, staleness: StalenessInfo(lastUsedDate: nil),
            tier: .info, consequence: "Permanently deletes this device and its local data."
        )

        static func model(_ stage: AndroidToolsStage) -> AppModel {
            let model = AppModel.previewPopulated()
            model.androidToolsStage = stage
            return model
        }
    }
#endif
