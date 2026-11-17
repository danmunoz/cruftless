import Foundation

/// A temporary Derived Data root with per-project folders and the projects they record.
struct DerivedDataFixture {
    let base: URL
    let root: URL

    init() throws {
        base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
            .resolvingSymlinksInPath()
        root = base.appendingPathComponent("DerivedData", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    /// A project bundle that exists on disk.
    func makeProject(_ name: String) throws -> URL {
        let project = base.appendingPathComponent("Projects/\(name).xcodeproj", isDirectory: true)
        try FileManager.default.createDirectory(at: project, withIntermediateDirectories: true)
        return project
    }

    /// A project path that was never created.
    func missingProject(_ name: String) -> String {
        base.appendingPathComponent("Gone/\(name).xcodeproj").path(percentEncoded: false)
    }

    /// A Derived Data folder whose `info.plist` records `workspacePath`, or no plist when it is `nil`.
    @discardableResult
    func makeFolder(
        _ name: String,
        workspacePath: String?,
        format: PropertyListSerialization.PropertyListFormat = .xml
    ) throws -> URL {
        let folder = root.appendingPathComponent(name, isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        try Data(repeating: 0x41, count: 4096).write(to: folder.appendingPathComponent("payload.bin"))
        if let workspacePath {
            try writeInfoPlist(["WorkspacePath": workspacePath, "LastAccessedDate": Date()], in: folder, format: format)
        }
        return folder
    }

    func writeInfoPlist(
        _ plist: [String: Any],
        in folder: URL,
        format: PropertyListSerialization.PropertyListFormat = .xml
    ) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
        try data.write(to: folder.appendingPathComponent("info.plist"))
    }
}
