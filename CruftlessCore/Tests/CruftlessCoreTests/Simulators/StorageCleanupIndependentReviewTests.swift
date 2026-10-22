@testable import CruftlessCore
import Foundation
import Testing

@Suite("Storage cleanup independent safety review")
struct StorageCleanupIndependentReviewTests {
    private let runtimeID = "com.apple.CoreSimulator.SimRuntime.iOS-18-6"
    private let udid = "01234567-89AB-CDEF-0123-456789ABCDEF"

    @Test("An image-only listing never establishes a missing runtime", arguments: [false, true])
    func imageListingIsNotAvailabilityAuthority(includeImage: Bool) throws {
        let images = includeImage ? [runtime()] : []
        let result = try #require(UnavailableDetector.reconcile(devices: [device()], runtimes: images).first)
        if case let .unknown(reason) = result.runtimeAvailability {
            #expect(!reason.isEmpty)
        } else {
            Issue.record("An image-only listing must leave runtime availability unknown")
        }
        #expect(!result.runtimeAvailability.isConfirmedMissing)
    }

    @Test("An absent full catalog without an error still means unknown")
    func absentCatalogIsNotEmptyCatalog() throws {
        let result = try #require(UnavailableDetector.reconcile(devices: [device()], catalog: nil).first)
        if case .unknown = result.runtimeAvailability {
            #expect(!result.runtimeAvailability.isConfirmedMissing)
        } else {
            Issue.record("No catalog is different from an authoritative empty catalog")
        }
        let empty = SimulatorRuntimeCatalog(runtimes: [])
        let missing = try #require(UnavailableDetector.reconcile(devices: [device()], catalog: empty).first)
        #expect(missing.runtimeAvailability == .missing)
    }

    @Test("A runtime deletion restriction does not disable its device")
    func deviceAuthorityIsIndependentOfRuntimeDeletion() throws {
        let generation = UUID()
        let catalog = SimulatorRuntimeCatalog(
            runtimes: [.init(identifier: runtimeID, version: "18.6", build: "22G86", isAvailable: true)],
            toolchainID: "review-toolchain", toolchainGeneration: generation
        )
        let listing = SimulatorRuntimeListing(
            runtimes: [runtime()], toolchainID: "review-toolchain", toolchainGeneration: generation,
            installedCatalog: catalog
        )
        let result = try #require(SimulatorService.reconcile([device()], against: listing).first)
        #expect(result.runtimeAvailability == .available)
        #expect(result.mutationIssue == nil)
        #expect(result.toolchainGeneration == generation)
        #expect(!runtime().canPlanDelete)
    }

    @Test("An installed unavailable runtime never selects missing-runtime device deletion")
    func installedUnavailableDoesNotSelectDelete() throws {
        let generation = UUID()
        let catalog = SimulatorRuntimeCatalog(
            runtimes: [.init(
                identifier: runtimeID, version: "18.6", build: "22G86", isAvailable: false,
                availabilityError: "The selected Xcode cannot use this installed runtime"
            )],
            toolchainID: "review-toolchain", toolchainGeneration: generation
        )
        let listing = SimulatorRuntimeListing(
            runtimes: [runtime()], toolchainID: "review-toolchain", toolchainGeneration: generation,
            installedCatalog: catalog
        )
        let result = try #require(SimulatorService.reconcile([device()], against: listing).first)
        #expect(!result.runtimeAvailability.isConfirmedMissing)
        let plan = try DeletionPlanner.simulatorDevices([(result, 100)], context: PlanningContext())
        guard case .simulatorErase = try #require(plan.items.first) else {
            Issue.record("An installed runtime must not cause the missing-runtime full device delete route")
            return
        }
    }

    @Test("An adapter without scoped commands refuses XCTest without deleting an ordinary device")
    func scopedCommandCannotDowngrade() async {
        let adapter = MockSimulatorExecutor()
        await #expect(throws: SimctlError.self) {
            try await adapter.deleteTestSimulator(udid: udid, deviceSet: .xctest())
        }
        #expect(adapter.log.commands.isEmpty)
    }

    @Test("Direct planners refuse unknown availability even with management command authority")
    func directPlannersRequireAvailabilityAuthority() throws {
        let listing = SimulatorRuntimeListing(
            runtimes: [runtime()], toolchainID: "review-toolchain", toolchainGeneration: UUID()
        )
        let result = try #require(SimulatorService.reconcile([device()], against: listing).first)
        #expect(!result.runtimeAvailability.isConfirmedMissing)
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.simulatorErase(for: result, context: PlanningContext())
        }
        #expect(throws: DeletionPlanningError.self) {
            try DeletionPlanner.simulatorDelete(for: result, context: PlanningContext())
        }
    }

    private func device() -> SimDevice {
        SimDevice(
            udid: udid, name: "Review device", runtime: runtimeID, state: .shutdown, lastUsedAt: nil,
            deviceDirectory: SimulatorDeviceSet.ordinary().root.appendingPathComponent(udid, isDirectory: true)
        )
    }

    private func runtime() -> SimRuntime {
        SimRuntime(
            identifier: runtimeID, runtimeIdentifier: runtimeID, name: "iOS 18.6", build: "22G86",
            sizeBytes: 100, isDeletable: false, mutationCapability: .unavailable("Manage this runtime in Xcode")
        )
    }
}
