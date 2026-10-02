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
        static let ambiguous = SimulatorToolchainResolution.unavailable(.ambiguous(candidateCount: 2))
        static let unavailable = SimulatorToolchainResolution.unavailable(.unavailable)
        static let loading: SimulatorToolchainResolution? = nil
    }
#endif
