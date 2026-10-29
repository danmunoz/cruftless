import CruftlessCore
import Foundation
import Testing

@Suite("Simulator batch planning")
struct SimulatorBatchPlanningTests {
    private let generation = UUID()
    private let context = PlanningContext(protectedPaths: ProtectedPaths(), policyGeneration: 17)

    private func device(
        _ udid: String,
        unavailable: Bool = false,
        state: SimDeviceState = .shutdown,
        generation: UUID? = nil,
        mutationIssue: String? = nil
    ) -> SimDevice {
        SimDevice(
            udid: udid,
            name: udid,
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            state: state,
            lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/\(udid)"),
            isUnavailable: unavailable,
            toolchainGeneration: generation,
            mutationIssue: mutationIssue
        )
    }

    private func runtime(
        _ identifier: String,
        generation: UUID? = nil,
        deletable: Bool = true,
        state: SimRuntimeState = .ready,
        capability: SimRuntimeMutationCapability = .available
    ) -> SimRuntime {
        SimRuntime(
            identifier: identifier,
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            name: identifier,
            build: "27A1",
            sizeBytes: 100,
            isDeletable: deletable,
            state: state,
            mutationCapability: capability,
            toolchainGeneration: generation
        )
    }

    @Test("Mixed healthy and unavailable devices retain erase/delete semantics and provenance")
    func mixedDevices() throws {
        let plan = try DeletionPlanner.simulatorDevices([
            (device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", unavailable: true, generation: generation), 80),
            (device("B93FB899-77F0-41C3-9A0C-45D22BFA0A93", state: .booted, generation: generation), 120)
        ], context: context)

        #expect(plan.count == 2)
        #expect(plan.confirmLabel == "Shut Down, Delete and Erase")
        #expect(plan.policyGeneration == 17)
        #expect(plan.simulatorToolchainGeneration == generation)
        #expect(plan.affectedLocationIds == [LocationCatalog.simulatorDevices.id])
        #expect(plan.items.contains { if case .simulatorDelete = $0 { true } else { false } })
        #expect(plan.items.contains { if case let .simulatorErase(_, _, booted, _, _) = $0 { booted } else { false } })
    }

    @Test("Booted healthy device keeps shutdown instruction in batch confirmation")
    func bootedDevice() throws {
        let plan = try DeletionPlanner.simulatorDevices([
            (device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", state: .booted, generation: generation), 120)
        ], context: context)
        #expect(plan.confirmLabel == "Shut Down and Erase")
    }

    @Test("Duplicate devices and inconsistent or absent toolchain generations are refused")
    func refusesInvalidDeviceBatches() {
        let first = device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        #expect(throws: DeletionPlanningError.duplicateTarget(name: LocationCatalog.simulatorDevices.title)) {
            try DeletionPlanner.simulatorDevices([(first, 10), (first, 20)], context: context)
        }
        #expect(throws: DeletionPlanningError.simulatorToolchainMismatch) {
            try DeletionPlanner.simulatorDevices([
                (first, 10),
                (device("B93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: UUID()), 20)
            ], context: context)
        }
        #expect(throws: DeletionPlanningError.simulatorToolchainMismatch) {
            try DeletionPlanner.simulatorDevices([(device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93"), 10)], context: context)
        }
    }

    @Test("Unsupported device and empty batch refuse the whole request")
    func refusesUnsupportedDevices() {
        #expect(throws: DeletionPlanningError.nothingToPlan(title: LocationCatalog.simulatorDevices.title)) {
            try DeletionPlanner.simulatorDevices([], context: context)
        }
        #expect(throws: DeletionPlanningError.runtimeToolingUnavailable(
            name: "A93FB899-77F0-41C3-9A0C-45D22BFA0A93",
            reason: "unsupported"
        )) {
            try DeletionPlanner.simulatorDevices([
                (device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation, mutationIssue: "unsupported"), 10)
            ], context: context)
        }
    }

    @Test("A protected descendant refuses a mixed device batch")
    func protectedDeviceRefusesWholeBatch() {
        let protected = URL(fileURLWithPath: "/tmp/A93FB899-77F0-41C3-9A0C-45D22BFA0A93/data/important", isDirectory: true)
        let first = device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        let second = device("B93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        let protectedContext = PlanningContext(protectedPaths: ProtectedPaths(customProtectedPaths: [protected]))
        #expect(throws: DeletionPlanningError.protectedDescendantInSimulator(
            name: first.name,
            path: first.deviceDirectory.path
        )) {
            try DeletionPlanner.simulatorDevices([(first, 10), (second, 20)], context: protectedContext)
        }
    }

    @Test("A protected ancestor of the simulator device refuses its batch")
    func protectedDeviceAncestorRefusesBatch() {
        let first = device("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        let protectedContext = PlanningContext(protectedPaths: ProtectedPaths(customProtectedPaths: [
            URL(fileURLWithPath: "/tmp", isDirectory: true)
        ]))
        #expect(throws: DeletionPlanningError.protectedDescendantInSimulator(
            name: first.name,
            path: first.deviceDirectory.path
        )) {
            try DeletionPlanner.simulatorDevices([(first, 10)], context: protectedContext)
        }
    }

    @Test("Runtime batch carries both invalidation scopes and shared provenance")
    func runtimeBatch() throws {
        let plan = try DeletionPlanner.simulatorRuntimes([
            runtime("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation),
            runtime("B93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        ], context: context)
        #expect(plan.count == 2)
        #expect(plan.simulatorToolchainGeneration == generation)
        #expect(plan.policyGeneration == 17)
        #expect(plan.affectedLocationIds == [
            LocationCatalog.simulatorRuntimes.id,
            LocationCatalog.simulatorDevices.id,
            LocationCatalog.xctestDevices.id
        ])
    }

    @Test("Duplicate, empty, mixed-generation, bundled, and removing runtimes refuse the full batch")
    func refusesRuntimeBatches() {
        let runtimeA = runtime("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        #expect(throws: DeletionPlanningError.nothingToPlan(title: LocationCatalog.simulatorRuntimes.title)) {
            try DeletionPlanner.simulatorRuntimes([], context: context)
        }
        #expect(throws: DeletionPlanningError.duplicateTarget(name: LocationCatalog.simulatorRuntimes.title)) {
            try DeletionPlanner.simulatorRuntimes([runtimeA, runtimeA], context: context)
        }
        #expect(throws: DeletionPlanningError.simulatorToolchainMismatch) {
            try DeletionPlanner.simulatorRuntimes([
                runtimeA,
                runtime("B93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: UUID())
            ], context: context)
        }
        #expect(throws: DeletionPlanningError.runtimeNotDeletable(name: "bundled")) {
            try DeletionPlanner.simulatorRuntimes([runtime("bundled", generation: generation, deletable: false)], context: context)
        }
        #expect(throws: DeletionPlanningError.runtimeBeingDeleted(name: "removing")) {
            try DeletionPlanner.simulatorRuntimes([runtime("removing", generation: generation, state: .deleting)], context: context)
        }
    }

    @Test("Protected descendants and ancestors in the runtime store refuse the whole batch")
    func protectedRuntimeStoreRefusesBatch() {
        let runtime = runtime("A93FB899-77F0-41C3-9A0C-45D22BFA0A93", generation: generation)
        let protectedContext = PlanningContext(protectedPaths: ProtectedPaths(customProtectedPaths: [
            URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Profiles/Runtimes/keep", isDirectory: true)
        ]))
        #expect(throws: DeletionPlanningError.protectedDescendantInSimulator(
            name: runtime.name,
            path: "/Library/Developer/CoreSimulator"
        )) {
            try DeletionPlanner.simulatorRuntimes([runtime], context: protectedContext)
        }

        let ancestorContext = PlanningContext(protectedPaths: ProtectedPaths(customProtectedPaths: [
            URL(fileURLWithPath: "/Library/Developer", isDirectory: true)
        ]))
        #expect(throws: DeletionPlanningError.protectedDescendantInSimulator(
            name: runtime.name,
            path: "/Library/Developer/CoreSimulator"
        )) {
            try DeletionPlanner.simulatorRuntimes([runtime], context: ancestorContext)
        }
    }
}
