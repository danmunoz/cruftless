import Darwin
import Foundation

/// One filesystem object as the walker sees it, read without following symlinks.
struct WalkEntry {
    enum Kind {
        case directory
        case regular
        case symlink
        case other
    }

    let name: String
    let kind: Kind
    let device: Int32
    let inode: UInt64
    let linkCount: UInt32
    let allocatedBytes: Int64
    /// Bytes only this object uses; equals `allocatedBytes` when the volume cannot tell.
    let exclusiveBytes: Int64
    /// The clone family this file shares blocks with, when it shares any.
    let cloneFamily: CloneFamilyMember?
    let modificationTime: timespec
    let creationTime: timespec
    let isMountPoint: Bool

    var modificationDate: Date { Date(timespec: modificationTime) }
    var creationDate: Date { Date(timespec: creationTime) }
}

/// Which entries a bulk read decodes names for; a file's name is only needed when its path is.
enum EntryNames {
    case all
    case directoriesOnly
}

/// Reads entries with `getattrlist(2)` and `getattrlistbulk(2)`, including APFS clone accounting.
enum DirectoryEntryReader {
    private static let bulkBufferSize = 32 * 1024
    private static let singleBufferSize = 1024

    private static let commonAttributes = attrgroup_t(ATTR_CMN_RETURNED_ATTRS) | attrgroup_t(ATTR_CMN_NAME)
        | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE) | attrgroup_t(ATTR_CMN_CRTIME)
        | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FLAGS) | attrgroup_t(ATTR_CMN_FILEID)
    private static let directoryAttributes = attrgroup_t(ATTR_DIR_MOUNTSTATUS)
    private static let fileAttributes = attrgroup_t(ATTR_FILE_LINKCOUNT) | attrgroup_t(ATTR_FILE_ALLOCSIZE)
    private static let extendedAttributes = attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) | attrgroup_t(ATTR_CMNEXT_CLONEID)
        | attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT)

    /// Reads the object at `path` itself, falling back to `lstat` when `getattrlist` cannot answer.
    static func entry(atPath path: String) -> WalkEntry? {
        var request = attributeRequest(common: commonAttributes)
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: singleBufferSize, alignment: 8)
        defer { buffer.deallocate() }
        let options = UInt32(FSOPT_NOFOLLOW) | UInt32(FSOPT_ATTR_CMN_EXTENDED)
        if getattrlist(path, &request, buffer, singleBufferSize, options) == 0,
           let entry = parse(UnsafeRawPointer(buffer), expectsError: false, names: .all) {
            return entry
        }
        return statEntry(atPath: path)
    }

    /// Calls `body` with each entry of the directory at `path`; returns false when the directory cannot be opened or read.
    static func forEachEntry(inDirectory path: String, names: EntryNames = .all, _ body: (WalkEntry) -> Void) -> Bool {
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }

        var request = attributeRequest(common: commonAttributes | attrgroup_t(ATTR_CMN_ERROR))
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: bulkBufferSize, alignment: 8)
        defer { buffer.deallocate() }

        while true {
            let count = getattrlistbulk(descriptor, &request, buffer, bulkBufferSize, UInt64(FSOPT_ATTR_CMN_EXTENDED))
            if count == 0 { return true }
            if count < 0 { return false }

            var record = UnsafeRawPointer(buffer)
            for _ in 0 ..< count {
                let length = Int(record.loadUnaligned(as: UInt32.self))
                if let entry = parse(record, expectsError: true, names: names) {
                    body(entry)
                } else if let name = entryName(record), let entry = statEntry(atPath: childPath(path, name)) {
                    body(entry)
                }
                record += length
            }
        }
    }

    static func childPath(_ parent: String, _ name: String) -> String {
        parent.hasSuffix("/") ? parent + name : parent + "/" + name
    }

    private static func attributeRequest(common: attrgroup_t) -> attrlist {
        var request = attrlist()
        request.bitmapcount = u_short(ATTR_BIT_MAP_COUNT)
        request.commonattr = common
        request.dirattr = directoryAttributes
        request.fileattr = fileAttributes
        request.forkattr = extendedAttributes
        return request
    }

    /// Parses one record; attributes are packed in group order, then bit order, for the bits the kernel returned.
    private static func parse(_ record: UnsafeRawPointer, expectsError: Bool, names: EntryNames) -> WalkEntry? {
        var cursor = AttributeCursor(pointer: record + MemoryLayout<UInt32>.size)
        let returned = cursor.read(attribute_set_t.self)
        let common = returned.commonattr

        if expectsError, common & attrgroup_t(ATTR_CMN_ERROR) != 0, cursor.read(UInt32.self) != 0 {
            return nil
        }
        let required = attrgroup_t(ATTR_CMN_NAME) | attrgroup_t(ATTR_CMN_DEVID) | attrgroup_t(ATTR_CMN_OBJTYPE)
            | attrgroup_t(ATTR_CMN_CRTIME) | attrgroup_t(ATTR_CMN_MODTIME) | attrgroup_t(ATTR_CMN_FILEID)
        guard common & required == required else { return nil }

        let nameReference = cursor.skipName()
        let device = cursor.read(Int32.self)
        let objectType = cursor.read(UInt32.self)
        let creation = cursor.read(timespec.self)
        let modification = cursor.read(timespec.self)
        let flags = common & attrgroup_t(ATTR_CMN_FLAGS) != 0 ? cursor.read(UInt32.self) : 0
        let inode = cursor.read(UInt64.self)

        let mountStatus = returned.dirattr & attrgroup_t(ATTR_DIR_MOUNTSTATUS) != 0 ? cursor.read(UInt32.self) : 0
        let linkCount = returned.fileattr & attrgroup_t(ATTR_FILE_LINKCOUNT) != 0 ? cursor.read(UInt32.self) : 1
        let allocated = returned.fileattr & attrgroup_t(ATTR_FILE_ALLOCSIZE) != 0 ? cursor.read(Int64.self) : 0
        let sharing = cursor.readSharing(returned.forkattr)

        let kind = WalkEntry.Kind(objectType: objectType)
        let name = names == .all || kind == .directory ? AttributeCursor.name(at: nameReference) : ""
        // Compressed data is not counted in the private size, so a compressed file keeps its allocated size.
        let reportsSharing = kind == .regular && flags & UInt32(UF_COMPRESSED) == 0
        let (exclusive, family) = reportsSharing ? sharing.split(allocated: allocated, device: device) : (allocated, nil)

        return WalkEntry(
            name: name,
            kind: kind,
            device: device,
            inode: inode,
            linkCount: linkCount,
            allocatedBytes: allocated,
            exclusiveBytes: exclusive,
            cloneFamily: family,
            modificationTime: modification,
            creationTime: creation,
            isMountPoint: mountStatus & UInt32(DIR_MNTSTATUS_MNTPOINT) != 0
        )
    }

    private static func entryName(_ record: UnsafeRawPointer) -> String? {
        var cursor = AttributeCursor(pointer: record + MemoryLayout<UInt32>.size)
        let common = cursor.read(attribute_set_t.self).commonattr
        if common & attrgroup_t(ATTR_CMN_ERROR) != 0 { _ = cursor.read(UInt32.self) }
        guard common & attrgroup_t(ATTR_CMN_NAME) != 0 else { return nil }
        return cursor.readName()
    }

    private static func statEntry(atPath path: String) -> WalkEntry? {
        var info = stat()
        guard lstat(path, &info) == 0 else { return nil }
        let allocated = Int64(info.st_blocks) * 512
        return WalkEntry(
            name: (path as NSString).lastPathComponent,
            kind: WalkEntry.Kind(mode: info.st_mode),
            device: info.st_dev,
            inode: info.st_ino,
            linkCount: UInt32(info.st_nlink),
            allocatedBytes: allocated,
            exclusiveBytes: allocated,
            cloneFamily: nil,
            modificationTime: info.st_mtimespec,
            creationTime: info.st_birthtimespec,
            isMountPoint: false
        )
    }
}

/// How a regular file's blocks are shared with APFS clones.
private struct BlockSharing {
    let privateBytes: Int64?
    let cloneID: UInt64?
    let cloneCount: UInt32?

    /// The bytes only this file uses, and its clone family when it shares blocks with one.
    func split(allocated: Int64, device: Int32) -> (Int64, CloneFamilyMember?) {
        guard let privateBytes, privateBytes >= 0, privateBytes <= allocated else { return (allocated, nil) }
        guard let cloneID, let cloneCount, cloneCount > 1, allocated > privateBytes else { return (privateBytes, nil) }
        let member = CloneFamilyMember(
            key: CloneFamilyKey(device: device, identifier: cloneID),
            memberCount: cloneCount,
            sharedBytes: allocated - privateBytes
        )
        return (privateBytes, member)
    }
}

private struct AttributeCursor {
    var pointer: UnsafeRawPointer

    mutating func read<Value: BitwiseCopyable>(_: Value.Type) -> Value {
        let value = pointer.loadUnaligned(as: Value.self)
        pointer += MemoryLayout<Value>.size
        return value
    }

    /// Reads an `attrreference_t`, whose offset is relative to the reference itself.
    mutating func readName() -> String {
        Self.name(at: skipName())
    }

    /// Reads the `ATTR_CMNEXT_*` sharing attributes the kernel returned.
    mutating func readSharing(_ returned: attrgroup_t) -> BlockSharing {
        BlockSharing(
            privateBytes: returned & attrgroup_t(ATTR_CMNEXT_PRIVATESIZE) != 0 ? read(Int64.self) : nil,
            cloneID: returned & attrgroup_t(ATTR_CMNEXT_CLONEID) != 0 ? read(UInt64.self) : nil,
            cloneCount: returned & attrgroup_t(ATTR_CMNEXT_CLONE_REFCNT) != 0 ? read(UInt32.self) : nil
        )
    }

    /// Steps over an `attrreference_t` and returns where it starts.
    mutating func skipName() -> UnsafeRawPointer {
        let reference = pointer
        pointer += MemoryLayout<attrreference_t>.size
        return reference
    }

    static func name(at reference: UnsafeRawPointer) -> String {
        let value = reference.loadUnaligned(as: attrreference_t.self)
        return String(cString: (reference + Int(value.attr_dataoffset)).assumingMemoryBound(to: CChar.self))
    }
}

private extension WalkEntry.Kind {
    init(objectType: UInt32) {
        switch objectType {
        case UInt32(VDIR.rawValue): self = .directory
        case UInt32(VREG.rawValue): self = .regular
        case UInt32(VLNK.rawValue): self = .symlink
        default: self = .other
        }
    }

    init(mode: mode_t) {
        switch mode & S_IFMT {
        case S_IFDIR: self = .directory
        case S_IFREG: self = .regular
        case S_IFLNK: self = .symlink
        default: self = .other
        }
    }
}

extension Date {
    init(timespec value: timespec) {
        self.init(timeIntervalSince1970: TimeInterval(value.tv_sec) + TimeInterval(value.tv_nsec) / 1_000_000_000)
    }
}
