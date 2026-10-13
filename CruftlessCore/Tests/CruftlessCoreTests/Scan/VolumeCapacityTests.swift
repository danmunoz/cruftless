@testable import CruftlessCore
import Testing

@Suite("Volume capacity")
struct VolumeCapacityTests {
    @Test("Physical free space is separate from the additional reclaimable allowance")
    func separatesFreeAndPurgeable() {
        let capacity = VolumeCapacity(
            totalBytes: 494_384_795_648,
            physicalFreeBytes: 13_412_016_128,
            importantAvailableBytes: 15_244_398_592
        )

        #expect(capacity.freeBytes == 13_412_016_128)
        #expect(capacity.purgeableBytes == 1_832_382_464)
        #expect(capacity.usedBytes == 479_140_397_056)
        #expect(capacity.freeBytes + capacity.purgeableBytes + capacity.usedBytes == capacity.totalBytes)
    }

    @Test("A missing reclaimable allowance preserves physical free space")
    func missingImportantCapacity() {
        let capacity = VolumeCapacity(totalBytes: 100, physicalFreeBytes: 20, importantAvailableBytes: nil)

        #expect(capacity.freeBytes == 20)
        #expect(capacity.purgeableBytes == 0)
        #expect(capacity.usedBytes == 80)
    }

    @Test("An allowance below physical free space never reduces free space", arguments: [Int64(-1), 0, 10, 20])
    func smallerImportantCapacity(important: Int64) {
        let capacity = VolumeCapacity(totalBytes: 100, physicalFreeBytes: 20, importantAvailableBytes: important)

        #expect(capacity.freeBytes == 20)
        #expect(capacity.purgeableBytes == 0)
        #expect(capacity.usedBytes == 80)
    }

    @Test("Reported capacity partitions stay within the volume", arguments: [
        (Int64(100), Int64(120), Int64(150)),
        (100, 20, 150),
        (100, -10, -20),
        (-100, 20, 30),
        (0, 0, 0),
        (Int64.max, Int64.max, Int64.max)
    ])
    func boundedCapacity(total: Int64, physicalFree: Int64, important: Int64) {
        let capacity = VolumeCapacity(
            totalBytes: total,
            physicalFreeBytes: physicalFree,
            importantAvailableBytes: important
        )

        #expect(capacity.totalBytes == max(0, total))
        #expect(capacity.freeBytes >= 0)
        #expect(capacity.purgeableBytes >= 0)
        #expect(capacity.usedBytes >= 0)
        #expect(capacity.freeBytes + capacity.purgeableBytes + capacity.usedBytes == capacity.totalBytes)
    }
}
