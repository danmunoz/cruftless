import Foundation

public struct VolumeCapacity: Sendable, Hashable {
    public let totalBytes: Int64
    public let freeBytes: Int64
    public let purgeableBytes: Int64
    public let usedBytes: Int64

    public init(
        totalBytes: Int64,
        freeBytes: Int64,
        purgeableBytes: Int64,
        usedBytes: Int64
    ) {
        self.totalBytes = totalBytes
        self.freeBytes = freeBytes
        self.purgeableBytes = purgeableBytes
        self.usedBytes = usedBytes
    }

    /// Queries the volume containing `url` (defaults to root system volume).
    public static func query(for url: URL = URL(fileURLWithPath: "/")) -> VolumeCapacity {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityForOpportunisticUsageKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return VolumeCapacity(totalBytes: 0, freeBytes: 0, purgeableBytes: 0, usedBytes: 0)
        }

        let total = Int64(values.volumeTotalCapacity ?? 0)
        let important = Int64(values.volumeAvailableCapacityForImportantUsage ?? 0)
        let opportunistic = Int64(values.volumeAvailableCapacityForOpportunisticUsage ?? 0)

        let purgeable = max(0, important - opportunistic)
        let free = max(0, opportunistic)
        let nonFree = max(0, total - free - purgeable)

        return VolumeCapacity(
            totalBytes: total,
            freeBytes: free,
            purgeableBytes: purgeable,
            usedBytes: nonFree
        )
    }
}
