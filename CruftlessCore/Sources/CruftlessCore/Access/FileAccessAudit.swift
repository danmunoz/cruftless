import Darwin
import Foundation
import Synchronization

/// One open or directory listing about to happen.
package struct FileAccessEvent: Sendable, Hashable {
    package enum Kind: Sendable, Hashable {
        case open
        case list
    }

    package let kind: Kind
    package let path: String
}

/// The seam every content read and directory listing on the scan's paths reports through, so tests can count them.
package enum FileAccessAudit {
    private static let isObserved = Atomic<Bool>(false)
    private static let observers = Mutex<[UInt64: @Sendable (FileAccessEvent) -> Void]>([:])
    private static let nextToken = Atomic<UInt64>(0)

    package static func record(_ kind: FileAccessEvent.Kind, _ path: String) {
        guard isObserved.load(ordering: .relaxed) else { return }
        let event = FileAccessEvent(kind: kind, path: path)
        let current = observers.withLock { Array($0.values) }
        for observer in current {
            observer(event)
        }
    }

    /// Starts delivering events to `observer` until the returned token is passed to `stopObserving`.
    package static func observe(_ observer: @escaping @Sendable (FileAccessEvent) -> Void) -> UInt64 {
        let token = nextToken.wrappingAdd(1, ordering: .relaxed).newValue
        observers.withLock { $0[token] = observer }
        isObserved.store(true, ordering: .relaxed)
        return token
    }

    package static func stopObserving(_ token: UInt64) {
        let isEmpty = observers.withLock { current -> Bool in
            current[token] = nil
            return current.isEmpty
        }
        if isEmpty { isObserved.store(false, ordering: .relaxed) }
    }

    /// `opendir`, reported as a listing.
    package static func openDirectory(_ path: String) -> UnsafeMutablePointer<DIR>? {
        record(.list, path)
        return opendir(path)
    }

    /// `FileManager.contentsOfDirectory`, reported as a listing.
    package static func contentsOfDirectory(atPath path: String, fileManager: FileManager = .default) -> [String]? {
        record(.list, path)
        return try? fileManager.contentsOfDirectory(atPath: path)
    }

    /// `Data(contentsOf:)`, reported as an open.
    package static func data(contentsOf url: URL) -> Data? {
        record(.open, url.path(percentEncoded: false))
        return try? Data(contentsOf: url)
    }
}
