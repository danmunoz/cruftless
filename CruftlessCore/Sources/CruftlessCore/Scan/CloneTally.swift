import Foundation

/// An APFS clone family: files whose data blocks are shared copy-on-write.
struct CloneFamilyKey: Hashable {
    let device: Int32
    let identifier: UInt64
}

/// One file's membership in a clone family, as `getattrlist` reports it.
struct CloneFamilyMember {
    let key: CloneFamilyKey
    /// Files in the family, this one included.
    let memberCount: UInt32
    /// Blocks this file shares with the rest of its family.
    let sharedBytes: Int64
}

/// Counts a clone family's shared blocks once, and only when every member is inside the measured tree.
struct CloneTally {
    private struct OpenFamily {
        var found: UInt32
        let memberCount: UInt32
        var sharedBytes: Int64
    }

    private(set) var completedSharedBytes: Int64 = 0
    private var openFamilies: [CloneFamilyKey: OpenFamily] = [:]

    mutating func record(_ member: CloneFamilyMember) {
        add(member.key, OpenFamily(found: 1, memberCount: member.memberCount, sharedBytes: member.sharedBytes))
    }

    mutating func merge(_ other: CloneTally) {
        completedSharedBytes += other.completedSharedBytes
        for (key, family) in other.openFamilies {
            add(key, family)
        }
    }

    private mutating func add(_ key: CloneFamilyKey, _ family: OpenFamily) {
        var merged = openFamilies[key] ?? OpenFamily(found: 0, memberCount: family.memberCount, sharedBytes: 0)
        merged.found += family.found
        merged.sharedBytes = max(merged.sharedBytes, family.sharedBytes)
        if merged.found >= merged.memberCount {
            openFamilies[key] = nil
            completedSharedBytes += merged.sharedBytes
        } else {
            openFamilies[key] = merged
        }
    }
}
