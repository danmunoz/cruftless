import CruftlessCore
import Foundation
import Testing

@Suite("ScanEngine sizes the simulator runtimes location")
struct ScanEngineRuntimesTests {
    private static func runtime(name: String, sizeBytes: Int64) -> SimRuntime {
        SimRuntime(
            identifier: "com.apple.CoreSimulator.SimRuntime.\(name)",
            runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.\(name)",
            name: name,
            build: "24A5418b",
            sizeBytes: sizeBytes,
            isDeletable: true
        )
    }

    private static func events(
        _ location: TrackedLocation,
        lister: @escaping ScanEngine.RuntimeLister
    ) async -> [ScanEvent] {
        let engine = ScanEngine(runtimeLister: lister)
        var collected: [ScanEvent] = []
        for await event in await engine.scan(catalog: [location]) {
            collected.append(event)
        }
        return collected
    }

    @Test("A stubbed runtime list yields a sized entry summing every runtime")
    func stubbedRuntimesAreSized() async {
        let events = await Self.events(LocationCatalog.simulatorRuntimes) {
            [
                Self.runtime(name: "iOS-27-0", sizeBytes: 8_000_000_000),
                Self.runtime(name: "watchOS-12-0", sizeBytes: 3_000_000_000)
            ]
        }

        let entries = events.compactMap { event -> InventoryEntry? in
            if case let .locationScanned(entry) = event { return entry }
            return nil
        }

        #expect(entries.count == 1)
        let entry = try? #require(entries.first)
        #expect(entry?.reclaimableBytes == 11_000_000_000)
        #expect(entry?.isUnavailable == false)
        #expect(entry?.roots.isEmpty == true)
        #expect(entry?.staleness.lastUsedDate == nil)
    }

    @Test("An empty runtime list is still a row, at zero bytes")
    func emptyRuntimeListIsStillARow() async {
        let events = await Self.events(LocationCatalog.simulatorRuntimes) { [] }
        let entries = events.compactMap { event -> InventoryEntry? in
            if case let .locationScanned(entry) = event { return entry }
            return nil
        }

        #expect(entries.count == 1)
        #expect(entries.first?.reclaimableBytes == 0)
    }

    @Test("A throwing runtime lister yields an unavailable entry, not a missing row")
    func throwingListerYieldsUnavailable() async {
        let events = await Self.events(LocationCatalog.simulatorRuntimes) {
            throw SimulatorServiceError.runtimesUnavailable("simctl timed out")
        }

        let entries = events.compactMap { event -> InventoryEntry? in
            if case let .locationScanned(entry) = event { return entry }
            return nil
        }

        #expect(entries.count == 1)
        #expect(entries.first?.isUnavailable == true)
        #expect(entries.first?.unavailableReason?.contains("simctl timed out") == true)
    }

    @Test("The engine still constructs without an injected runtime lister")
    func defaultInitialiserExists() async {
        let engine = ScanEngine()
        #expect(await engine.cachedInventory() == nil)
    }
}

@Suite("ScanEngine bounds simctl on the scan path")
struct ScanEngineSimctlTimeoutTests {
    @Test("The scan's simctl ceiling is far below the deletion ceiling")
    func scanTimeoutIsShorterThanDeletionTimeout() {
        #expect(ScanEngine.simctlScanTimeout < DefaultSimctlExecutor.defaultTimeout)
        #expect(ScanEngine.simctlScanTimeout >= .seconds(5))
        #expect(ScanEngine.simctlScanTimeout <= .seconds(20))
    }
}
