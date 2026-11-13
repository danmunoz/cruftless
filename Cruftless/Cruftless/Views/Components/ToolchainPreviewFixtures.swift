#if DEBUG
    import CruftlessCore
    import Foundation

    enum ToolchainPreviewFixtures {
        static let stable = SimulatorToolchain(
            id: "/Applications/Xcode.app",
            appURL: URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true),
            developerDirectory: URL(fileURLWithPath: "/Applications/Xcode.app/Contents/Developer", isDirectory: true),
            version: "27.0"
        )

        static let beta = SimulatorToolchain(
            id: "/Applications/Xcode-beta.app",
            appURL: URL(fileURLWithPath: "/Applications/Xcode-beta.app", isDirectory: true),
            developerDirectory: URL(fileURLWithPath: "/Applications/Xcode-beta.app/Contents/Developer", isDirectory: true),
            version: "27.1beta1"
        )

        static let ready = SimulatorToolchainResolution.ready(stable, source: .discovered, generation: UUID())
        static let userSelected = SimulatorToolchainResolution.ready(stable, source: .userSelected, generation: UUID())
        static let ambiguous = SimulatorToolchainResolution.unavailable(.ambiguous(candidateCount: 2))
        static let unavailable = SimulatorToolchainResolution.unavailable(.unavailable)
        static let loading: SimulatorToolchainResolution? = nil

        static let reportText = """
        Cruftless Diagnostic Report
        Schema: 1
        Simulator toolchain: available
        Xcode A: 27.0
        """
    }

    @MainActor
    extension AppModel {
        /// A model whose cleanup is running, so Settings controls that touch the scan are disabled.
        static func previewDeletionRunning() -> AppModel {
            let model = AppModel()
            model.settings.isDeletionExecuting = true
            return model
        }
    }
#endif
