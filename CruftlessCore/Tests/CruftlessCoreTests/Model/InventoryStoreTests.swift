import CruftlessCore
import Foundation
import Testing

@Suite("InventoryStore Tests")
struct InventoryStoreTests {
    private let capacity = VolumeCapacity(
        totalBytes: 1_000_000,
        freeBytes: 400_000,
        purgeableBytes: 50_000,
        usedBytes: 550_000
    )

    private func temporaryDirectory() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("InventoryStoreTests-\(UUID().uuidString)", isDirectory: true)
    }

    private func snapshot(bytes: Int64 = 4_096) -> InventorySnapshot {
        InventorySnapshot(
            Inventory(
                entries: [
                    .sized(
                        location: LocationCatalog.derivedData,
                        reclaimableBytes: bytes,
                        staleness: StalenessInfo(lastUsedDate: nil),
                        roots: []
                    )
                ],
                capacity: capacity,
                scannedAt: Date(timeIntervalSince1970: 1_000_000)
            )
        )
    }

    @Test("Saving then loading returns the same snapshot")
    func roundTrips() throws {
        let store = InventoryStore(directory: temporaryDirectory())
        let original = snapshot()

        store.save(original)

        #expect(store.load() == original)
    }

    @Test("Saving creates the directory it needs")
    func createsDirectory() throws {
        let directory = temporaryDirectory().appendingPathComponent("nested", isDirectory: true)
        let store = InventoryStore(directory: directory)

        store.save(snapshot())

        #expect(store.load() != nil)
    }

    @Test("A second save replaces the first")
    func overwrites() throws {
        let store = InventoryStore(directory: temporaryDirectory())

        store.save(snapshot(bytes: 1))
        store.save(snapshot(bytes: 2))

        #expect(store.load()?.rows.first?.kind == .sized(bytes: 2))
    }

    @Test("A missing file loads as nothing, not as an error")
    func missingFile() {
        #expect(InventoryStore(directory: temporaryDirectory()).load() == nil)
    }

    @Test("Malformed JSON loads as nothing rather than throwing")
    func malformedFile() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("not json".utf8).write(to: directory.appendingPathComponent("inventory.json"))

        #expect(InventoryStore(directory: directory).load() == nil)
    }

    @Test("A save that cannot be written fails quietly")
    func unwritableDirectory() throws {
        let directory = temporaryDirectory()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try Data("blocked".utf8).write(to: directory.appendingPathComponent("blocking"))
        let store = InventoryStore(directory: directory.appendingPathComponent("blocking", isDirectory: true))

        store.save(snapshot())

        #expect(store.load() == nil)
    }
}
