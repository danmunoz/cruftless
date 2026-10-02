@testable import CruftlessCore
import Foundation
import Synchronization
import Testing

@Suite("Simulator catalog authority")
struct SimulatorCatalogAuthorityTests {
    private let generation = UUID()
    private let runtimeID = "com.apple.CoreSimulator.SimRuntime.iOS-27-0"

    @Test("A successful empty runtime catalog preserves command authority")
    func emptyCatalog() async throws {
        let runner = SimctlRunner(executor: CatalogOutputExecutor(output: SimctlOutput(
            status: 0, stdout: "{}", stderr: "", toolchainID: "fixture", toolchainGeneration: generation
        )))
        let listing = try await runner.listRuntimeCatalog()
        let reconciled = try #require(SimulatorService.reconcile([device()], against: listing).first)
        #expect(listing.runtimes.isEmpty)
        #expect(reconciled.isUnavailable)
        #expect(reconciled.mutationIssue == nil)
        #expect(reconciled.toolchainGeneration == generation)
        let plan = try DeletionPlanner.simulatorDelete(for: reconciled, context: PlanningContext())
        #expect(plan.simulatorToolchainGeneration == generation)
    }

    @Test("An unconfirmed runtime does not disable devices using a confirmed runtime")
    func unrelatedFallback() throws {
        let confirmed = runtime(runtimeID)
        let fallback = runtime("com.apple.CoreSimulator.SimRuntime.iOS-26-0", capability: .unavailable("unconfirmed"))
        let listing = SimulatorRuntimeListing(
            runtimes: [confirmed, fallback], toolchainID: "fixture", toolchainGeneration: generation
        )
        let reconciled = try #require(SimulatorService.reconcile([device()], against: listing).first)
        #expect(reconciled.mutationIssue == nil)
        #expect(!reconciled.isUnavailable)
        #expect(reconciled.toolchainGeneration == generation)
        let missing = try #require(SimulatorService.reconcile([device(runtime: "missing")], against: listing).first)
        #expect(missing.isUnavailable)
        #expect(missing.mutationIssue == nil)
        #expect(missing.toolchainGeneration == generation)
    }

    @Test("Fallback-only catalog refuses simulator and runtime mutation planning")
    func fallbackRefused() throws {
        let fallback = runtime(runtimeID, capability: .unavailable("tools unavailable"))
        let listing = SimulatorRuntimeListing(runtimes: [fallback], mutationIssue: "tools unavailable")
        let reconciled = try #require(SimulatorService.reconcile([device()], against: listing).first)
        #expect(reconciled.mutationIssue != nil)
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.simulatorDelete(for: reconciled, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.runtimeDelete(fallback, context: PlanningContext())
        }
    }

    @Test("Production executor refuses missing catalog authority without launching a command")
    func missingAuthorityDoesNotLaunch() async {
        let launches = Mutex(0)
        let subprocess = DefaultSimctlExecutor(
            timeout: .seconds(1), executableURL: URL(fileURLWithPath: "/usr/bin/true"), argumentPrefix: [],
            onLaunch: { _ in launches.withLock { $0 += 1 } },
            toolchainResolver: SimulatorToolchainResolver(candidates: { [] }, selectedDirectory: { nil })
        )
        let executor = DeletionExecutor(simulatorExecutor: DefaultSimulatorCommandExecutor(
            runner: SimctlRunner(executor: subprocess)
        ))
        let plan = DeletionPlan.single(.runtimeDelete(
            identifier: "01234567-89AB-CDEF-0123-456789ABCDEF", name: "Fixture runtime",
            consequence: "Fixture", reclaimableBytes: 100
        ))
        let result = await executor.execute(plan)
        #expect(launches.withLock { $0 } == 0)
        #expect(result.totalFreedBytes == 0)
        #expect(result.items.first?.status == .notAttempted(reason: .toolchainChanged))
    }

    private func device(runtime: String? = nil) -> SimDevice {
        SimDevice(
            udid: "01234567-89AB-CDEF-0123-456789ABCDEF", name: "Fixture device", runtime: runtime ?? runtimeID,
            state: .shutdown, lastUsedAt: nil, deviceDirectory: URL(fileURLWithPath: "/tmp/fixture-simulator-device")
        )
    }

    private func runtime(_ identifier: String, capability: SimRuntimeMutationCapability = .available) -> SimRuntime {
        SimRuntime(
            identifier: identifier, runtimeIdentifier: identifier, name: "Fixture runtime", build: "26A1",
            sizeBytes: 100, isDeletable: true, mutationCapability: capability,
            toolchainID: capability == .available ? "fixture" : nil,
            toolchainGeneration: capability == .available ? generation : nil
        )
    }
}

private struct CatalogOutputExecutor: SimctlExecuting {
    let output: SimctlOutput
    func run(arguments _: [String]) async throws -> SimctlOutput { output }
}
