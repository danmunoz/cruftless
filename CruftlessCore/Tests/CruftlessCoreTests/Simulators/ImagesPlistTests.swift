import CruftlessCore
import Foundation
import Testing

@Suite("ImagesPlist path handling")
struct ImagesPlistTests {
    @Test("ImagesPlist sizes a runtime whose path contains a space")
    func imagesPlistSizesPathWithSpace() throws {
        let imagesDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: imagesDirectory) }

        let relativeName = "iOS 18.6.simruntime"
        let runtimeFile = imagesDirectory.appendingPathComponent(relativeName)
        try Data(repeating: 0, count: 8192).write(to: runtimeFile)

        let plist = Data("""
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>images</key>
            <array>
                <dict>
                    <key>path</key>
                    <dict>
                        <key>relative</key>
                        <string>\(relativeName)</string>
                    </dict>
                    <key>runtimeInfo</key>
                    <dict>
                        <key>build</key>
                        <string>22G86</string>
                        <key>bundleIdentifier</key>
                        <string>com.apple.CoreSimulator.SimRuntime.iOS-18-6</string>
                    </dict>
                </dict>
            </array>
        </dict>
        </plist>
        """.utf8)

        let runtimes = ImagesPlist.parse(data: plist, imagesDirectory: imagesDirectory)
        let runtime = try #require(runtimes?.first)
        #expect(runtime.sizeBytes > 0)
    }

    @Test("ImagesPlist sizes a runtime whose path.relative is a file:// URL")
    func imagesPlistSizesFileURLPath() throws {
        let imagesDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: imagesDirectory) }

        let runtimeFile = imagesDirectory.appendingPathComponent("iOS 27.0.dmg")
        try Data(repeating: 0, count: 8192).write(to: runtimeFile)
        let fileURLString = "file://\(imagesDirectory.path)/iOS%2027.0.dmg"

        let runtimes = ImagesPlist.parse(
            data: try Self.plist(relativePath: fileURLString),
            imagesDirectory: imagesDirectory
        )
        let runtime = try #require(runtimes?.first)
        #expect(runtime.sizeBytes > 0)
    }

    @Test("ImagesPlist yields no size for a path.relative naming a directory")
    func imagesPlistDoesNotSizeADirectory() throws {
        let imagesDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("cruftless-images-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: imagesDirectory) }

        let assetData = imagesDirectory.appendingPathComponent("AssetData", isDirectory: true)
        try FileManager.default.createDirectory(at: assetData, withIntermediateDirectories: true)
        try Data(repeating: 0, count: 8192).write(to: assetData.appendingPathComponent("payload"))

        let runtimes = ImagesPlist.parse(
            data: try Self.plist(relativePath: "file://\(assetData.path)/"),
            imagesDirectory: imagesDirectory
        )
        let runtime = try #require(runtimes?.first)
        #expect(runtime.sizeBytes == 0)
    }

    private static func plist(relativePath: String) throws -> Data {
        let dict: [String: Any] = [
            "images": [
                [
                    "path": ["relative": relativePath],
                    "runtimeInfo": [
                        "build": "24A5423a",
                        "bundleIdentifier": "com.apple.CoreSimulator.SimRuntime.iOS-27-0"
                    ]
                ] as [String: Any]
            ]
        ]
        return try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
    }
}
