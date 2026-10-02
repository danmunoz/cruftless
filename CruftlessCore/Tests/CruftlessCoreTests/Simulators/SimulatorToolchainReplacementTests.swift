@testable import CruftlessCore
import Foundation
import Testing

@Suite("Simulator toolchain replacement")
struct SimulatorToolchainReplacementTests {
    @Test("A replaced Xcode at the same path invalidates a reviewed operation")
    func replacementInvalidatesLease() async throws {
        let app = URL(fileURLWithPath: "/Applications/Fixture-Xcode.app", isDirectory: true)
        let original = SimulatorToolchain(
            id: app.path,
            appURL: app,
            developerDirectory: app.appendingPathComponent("Contents/Developer", isDirectory: true),
            version: "27.0"
        )
        let replacement = SimulatorToolchain(
            id: app.path,
            appURL: app,
            developerDirectory: app.appendingPathComponent("Contents/Developer", isDirectory: true),
            version: "27.1"
        )
        let registry = ReplacementRegistry(original)
        let resolver = SimulatorToolchainResolver(
            candidates: { [app] },
            selectedDirectory: { nil },
            validator: { _ in await registry.current }
        )

        let generation = try #require(await resolver.resolve().generation)
        await registry.replace(with: replacement)

        #expect(await resolver.beginOperation(generation: generation) == false)
    }
}

private actor ReplacementRegistry {
    private(set) var current: SimulatorToolchain

    init(_ toolchain: SimulatorToolchain) {
        current = toolchain
    }

    func replace(with toolchain: SimulatorToolchain) {
        current = toolchain
    }
}
