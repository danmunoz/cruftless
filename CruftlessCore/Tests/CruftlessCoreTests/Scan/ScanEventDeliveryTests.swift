import CruftlessCore
import Foundation
import Testing

@Suite("Scan event delivery")
struct ScanEventDeliveryTests {
    private static func makeCatalog(under base: URL) throws -> [TrackedLocation] {
        try ["alpha", "beta", "gamma"].map { name in
            let root = base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for index in 0 ..< 4 {
                try Data(repeating: 0x41, count: 64).write(to: root.appendingPathComponent("f\(index)"))
            }
            return TrackedLocation(
                id: name,
                title: name,
                icon: .symbol("folder"),
                tier: .regen,
                hasDrillDown: false,
                stalenessSource: .topLevelMtime,
                resolveRoots: { [root] }
            )
        }
    }

    @Test("A row is delivered while another location is still being measured")
    func rowsArriveBeforeTheScanEnds() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-delivery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let walked = try Self.makeCatalog(under: base)

        // The runtimes row cannot land until the latch opens, and the latch opens only on the walked rows.
        let runtimesPending = AsyncLatch()
        let engine = ScanEngine(runtimeLister: {
            await runtimesPending.wait()
            return []
        })
        let catalog = walked + [LocationCatalog.simulatorRuntimes]

        var walkedRows: Set<String> = []
        var runtimesLanded = false
        for await event in await engine.scan(catalog: catalog) {
            guard case let .locationScanned(entry) = event else { continue }
            if entry.location.id == LocationCatalog.simulatorRuntimes.id {
                runtimesLanded = true
            } else {
                walkedRows.insert(entry.location.id)
                if walkedRows.count == walked.count { runtimesPending.open() }
            }
        }
        runtimesPending.open()

        #expect(walkedRows.count == walked.count)
        #expect(runtimesLanded)
        #expect(
            !runtimesPending.openedByFailsafe,
            "the walked rows were held back until the pending location finished"
        )
    }
}
