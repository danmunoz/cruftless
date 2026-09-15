import Darwin
import Foundation

enum TestFileSystem: Sendable {
    static func removeDirectoryRecursively(at url: URL) {
        let path = url.path(percentEncoded: false)
        removeRecursive(path: path)
    }

    static func removeFile(at url: URL) {
        unlink(url.path(percentEncoded: false))
    }

    private static func removeRecursive(path: String) {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: path, isDirectory: &isDir) else {
            return
        }

        if isDir.boolValue {
            if let subpaths = FileManager.default.subpaths(atPath: path) {
                for sub in subpaths.reversed() {
                    let fullPath = (path as NSString).appendingPathComponent(sub)
                    var subIsDir: ObjCBool = false
                    if FileManager.default.fileExists(atPath: fullPath, isDirectory: &subIsDir) {
                        if subIsDir.boolValue {
                            rmdir(fullPath)
                        } else {
                            unlink(fullPath)
                        }
                    }
                }
            }
            rmdir(path)
        } else {
            unlink(path)
        }
    }
}
