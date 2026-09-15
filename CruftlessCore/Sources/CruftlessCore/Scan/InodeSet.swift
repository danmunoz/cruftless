import Darwin
import Foundation

public struct InodeKey: Hashable, Sendable {
    public let device: Int32
    public let inode: UInt64

    public init(device: Int32, inode: UInt64) {
        self.device = device
        self.inode = inode
    }
}

/// Thread-safe tracking set for deduplicating hardlinks across scan roots.
public final class InodeSet: @unchecked Sendable {
    private var seen: Set<InodeKey> = []
    private let lock = NSLock()

    public init() {}

    /// Evaluates a hardlink (`linkCount > 1`).
    public func recordHardlinkIfFirstSeen(device: Int32, inode: UInt64) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        let key = InodeKey(device: device, inode: inode)
        return seen.insert(key).inserted
    }

    public func reset() {
        lock.lock()
        defer { lock.unlock() }
        seen.removeAll()
    }
}
