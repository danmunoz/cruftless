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

    init(totalBytes: Int64, physicalFreeBytes: Int64, importantAvailableBytes: Int64?) {
        let total = max(0, totalBytes)
        let free = min(total, max(0, physicalFreeBytes))
        let available = min(total, max(free, importantAvailableBytes ?? free))

        self.init(
            totalBytes: total,
            freeBytes: free,
            purgeableBytes: available - free,
            usedBytes: total - available
        )
    }

    /// Queries the volume containing `url` (defaults to root system volume).
    public static func query(for url: URL = URL(fileURLWithPath: "/")) -> VolumeCapacity {
        let keys: Set<URLResourceKey> = [
            .volumeTotalCapacityKey,
            .volumeAvailableCapacityKey,
            .volumeAvailableCapacityForImportantUsageKey
        ]

        guard let values = try? url.resourceValues(forKeys: keys) else {
            return VolumeCapacity(totalBytes: 0, freeBytes: 0, purgeableBytes: 0, usedBytes: 0)
        }

        return VolumeCapacity(
            totalBytes: Int64(values.volumeTotalCapacity ?? 0),
            physicalFreeBytes: Int64(values.volumeAvailableCapacity ?? 0),
            importantAvailableBytes: values.volumeAvailableCapacityForImportantUsage
        )
    }
}
