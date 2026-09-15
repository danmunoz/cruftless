import CruftlessCore
import Foundation
import Testing

@Suite("Scan event delivery")
struct ScanEventDeliveryTests {
    private static let filesPerRoot = 2000

    private static func makeCatalog(under base: URL) throws -> [TrackedLocation] {
        try ["alpha", "beta", "gamma"].map { name in
            let root = base.appendingPathComponent(name, isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
            for index in 0 ..< filesPerRoot {
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

    @Test("Rows are delivered as they land, not in one burst at the end")
    func rowsArriveIncrementally() async throws {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-delivery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: base) }
        let catalog = try Self.makeCatalog(under: base)

        let start = Date()
        var rowTimes: [TimeInterval] = []
        for await event in await ScanEngine().scan(catalog: catalog) {
            if case .locationScanned = event {
                rowTimes.append(Date().timeIntervalSince(start))
            }
        }

        #expect(rowTimes.count == catalog.count)
        let spread = (rowTimes.last ?? 0) - (rowTimes.first ?? 0)
        #expect(
            spread > 0.003,
            "every row arrived within \(Int(spread * 1000))ms of the first: they are being delivered in one burst"
        )
    }
}
