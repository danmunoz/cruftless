import Darwin
import Foundation

/// Durable identity records for Android Studio index directories atomically moved aside for cleanup.
public enum AndroidStudioIndexTombstone {
    static let maximumRecords = 128
    static let maximumRecordBytes = 16 * 1024
    static let recordPrefix = ".cruftless-index-removal-"
    static let tombstonePrefix = ".cruftless-index-tombstone-"

    public static var defaultRecordDirectory: URL? {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Cruftless/Android Studio Index Recovery", isDirectory: true)
    }

    static func recordDirectory(for home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Cruftless/Android Studio Index Recovery", isDirectory: true)
    }

    struct Record: Codable, Sendable, Equatable {
        let schemaVersion: Int
        let token: String
        let versionDirectoryPath: String
        let sourceInode: UInt64
        let sourceDevice: UInt64
        let sourceBirthTimeSeconds: Int64
        let sourceBirthTimeNanoseconds: Int64
    }

    struct Context: Sendable {
        let home: URL
        let protectedPaths: ProtectedPaths
        let recordDirectory: URL
    }

    enum State: Sendable, Equatable {
        case prepared
        case pending(URL)
        case completed
        case stale
    }

    struct Inspection: Sendable, Equatable {
        let recordURL: URL
        let state: State
    }

    enum StoreError: Error {
        case invalidSource
        case recordCollision
        case writeFailed
    }

    /// Creates a durable prepared record before the source directory is renamed.
    static func prepare(
        source: URL,
        fingerprint: Fingerprint,
        versionDirectory: URL,
        context: Context
    ) throws -> URL {
        guard let validatedVersion = AndroidStudioIndexPath.validateVersionDirectory(
            versionDirectory,
            home: context.home,
            protectedPaths: context.protectedPaths
        ),
        AndroidStudioIndexPath.validate(source, home: context.home, protectedPaths: context.protectedPaths) != nil,
        isSecureDirectory(context.recordDirectory, home: context.home)
        else { throw StoreError.invalidSource }

        let sourcePath = ProtectedPaths.standardize(source)
        let versionPath = ProtectedPaths.standardize(validatedVersion)
        guard sourcePath == (versionPath as NSString).appendingPathComponent("index"),
              fingerprint.path == sourcePath,
              fingerprint.isDirectory,
              let birthTimeSeconds = fingerprint.birthTimeSeconds,
              let birthTimeNanoseconds = fingerprint.birthTimeNanoseconds,
              let current = Fingerprint.capture(at: source),
              current.inode == fingerprint.inode,
              current.device == fingerprint.device,
              current.birthTimeSeconds == birthTimeSeconds,
              current.birthTimeNanoseconds == birthTimeNanoseconds
        else { throw StoreError.invalidSource }

        for _ in 0 ..< 3 {
            let token = UUID().uuidString.lowercased()
            let record = Record(
                schemaVersion: 1,
                token: token,
                versionDirectoryPath: versionPath,
                sourceInode: fingerprint.inode,
                sourceDevice: UInt64(UInt32(bitPattern: fingerprint.device)),
                sourceBirthTimeSeconds: birthTimeSeconds,
                sourceBirthTimeNanoseconds: birthTimeNanoseconds
            )
            let url = context.recordDirectory.appendingPathComponent(Self.recordName(token))
            switch write(record, at: url) {
            case .success: return url
            case .collision: continue
            case .failure: throw StoreError.writeFailed
            }
        }
        throw StoreError.recordCollision
    }

    /// Reads bounded records and reports only tombstones whose recorded inode and volume still match.
    static func inspect(
        versionDirectory: URL,
        context: Context
    ) -> [Inspection]? {
        guard let validatedVersion = AndroidStudioIndexPath.validateVersionDirectory(
            versionDirectory,
            home: context.home,
            protectedPaths: context.protectedPaths
        ),
        isSecureDirectory(context.recordDirectory, home: context.home),
        let names = try? FileManager.default.contentsOfDirectory(atPath: context.recordDirectory.path(percentEncoded: false)),
        names.count <= 16_384 else { return nil }

        let recordNames = names.filter(Self.isRecordName).sorted()
        guard recordNames.count <= maximumRecords else { return nil }

        return recordNames.compactMap { name in
            let recordURL = context.recordDirectory.appendingPathComponent(name)
            guard let record = readRecord(at: recordURL),
                  record.schemaVersion == 1,
                  record.token == Self.token(from: name),
                  record.versionDirectoryPath == ProtectedPaths.standardize(validatedVersion)
            else { return nil }

            let source = validatedVersion.appendingPathComponent("index", isDirectory: true)
            let tombstone = validatedVersion.appendingPathComponent(Self.tombstoneName(record.token), isDirectory: true)
            if matches(record, at: tombstone) {
                return Inspection(recordURL: recordURL, state: .pending(tombstone))
            }
            var tombstoneInfo = stat()
            if lstat(ProtectedPaths.standardize(tombstone), &tombstoneInfo) == 0 {
                return Inspection(recordURL: recordURL, state: .stale)
            }
            if matches(record, at: source) {
                return Inspection(recordURL: recordURL, state: .prepared)
            }
            var sourceInfo = stat()
            if lstat(ProtectedPaths.standardize(source), &sourceInfo) == 0 {
                return Inspection(recordURL: recordURL, state: .stale)
            }
            return Inspection(recordURL: recordURL, state: .completed)
        }
    }

    static func recordName(_ token: String) -> String {
        recordPrefix + token + ".json"
    }

    static func tombstoneName(_ token: String) -> String {
        tombstonePrefix + token
    }

    private enum WriteResult {
        case success
        case collision
        case failure
    }

    private static func write(_ record: Record, at url: URL) -> WriteResult {
        guard let data = try? JSONEncoder().encode(record), data.count <= maximumRecordBytes else { return .failure }
        let path = ProtectedPaths.standardize(url)
        let descriptor = Darwin.open(path, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard descriptor >= 0 else { return errno == EEXIST ? .collision : .failure }
        var written = 0
        while written < data.count {
            let result = data.withUnsafeBytes { bytes in
                Darwin.write(descriptor, bytes.baseAddress?.advanced(by: written), data.count - written)
            }
            if result < 0 {
                if errno == EINTR { continue }
                Darwin.close(descriptor)
                return .failure
            }
            guard result > 0 else {
                Darwin.close(descriptor)
                return .failure
            }
            written += result
        }
        guard Darwin.fsync(descriptor) == 0 else {
            Darwin.close(descriptor)
            return .failure
        }
        guard Darwin.close(descriptor) == 0 else { return .failure }
        let parent = Darwin.open(url.deletingLastPathComponent().path(percentEncoded: false), O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard parent >= 0 else { return .failure }
        defer { Darwin.close(parent) }
        return Darwin.fsync(parent) == 0 ? .success : .failure
    }

    static func readRecord(at url: URL) -> Record? {
        let descriptor = Darwin.open(ProtectedPaths.standardize(url), O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard descriptor >= 0 else { return nil }
        defer { Darwin.close(descriptor) }

        var fileInfo = stat()
        guard Darwin.fstat(descriptor, &fileInfo) == 0,
              (fileInfo.st_mode & S_IFMT) == S_IFREG,
              fileInfo.st_size > 0,
              fileInfo.st_size <= off_t(maximumRecordBytes)
        else { return nil }

        var data = Data(count: Int(fileInfo.st_size))
        var bytesRead = 0
        while bytesRead < data.count {
            let result = data.withUnsafeMutableBytes { buffer in
                Darwin.read(descriptor, buffer.baseAddress?.advanced(by: bytesRead), buffer.count - bytesRead)
            }
            if result < 0 {
                if errno == EINTR { continue }
                return nil
            }
            guard result > 0 else { return nil }
            bytesRead += result
        }
        return try? JSONDecoder().decode(Record.self, from: data)
    }

    private static func isSecureDirectory(_ url: URL, home: URL) -> Bool {
        guard url.isFileURL, url.host(percentEncoded: false)?.isEmpty != false else { return false }
        let path = ProtectedPaths.standardize(url)
        guard path == ProtectedPaths.standardize(recordDirectory(for: home)) else { return false }
        let components = (path as NSString).pathComponents
        var currentPath = ""
        for component in components {
            currentPath = currentPath.isEmpty ? component : (currentPath as NSString).appendingPathComponent(component)
            var info = stat()
            guard lstat(currentPath, &info) == 0,
                  (info.st_mode & S_IFMT) == S_IFDIR
            else { return false }
            let isHomeOrDescendant = currentPath == ProtectedPaths.standardize(home)
                || currentPath.hasPrefix(ProtectedPaths.standardize(home) + "/")
            if isHomeOrDescendant {
                guard info.st_uid == geteuid(), (info.st_mode & 0o022) == 0 else { return false }
            } else if (info.st_mode & 0o022) != 0, (info.st_mode & S_ISVTX) == 0 {
                return false
            }
        }
        return true
    }

    private static func matches(_ record: Record, at url: URL) -> Bool {
        var info = stat()
        guard lstat(ProtectedPaths.standardize(url), &info) == 0,
              (info.st_mode & S_IFMT) == S_IFDIR
        else { return false }
        return UInt64(info.st_ino) == record.sourceInode
            && UInt64(UInt32(bitPattern: Int32(info.st_dev))) == record.sourceDevice
            && Int64(info.st_birthtimespec.tv_sec) == record.sourceBirthTimeSeconds
            && Int64(info.st_birthtimespec.tv_nsec) == record.sourceBirthTimeNanoseconds
    }

    private static func isRecordName(_ name: String) -> Bool {
        guard name.hasPrefix(recordPrefix), name.hasSuffix(".json") else { return false }
        let token = String(name.dropFirst(recordPrefix.count).dropLast(".json".count))
        return UUID(uuidString: token)?.uuidString.lowercased() == token
    }

    static func token(from name: String) -> String? {
        guard isRecordName(name) else { return nil }
        return String(name.dropFirst(recordPrefix.count).dropLast(".json".count))
    }
}
