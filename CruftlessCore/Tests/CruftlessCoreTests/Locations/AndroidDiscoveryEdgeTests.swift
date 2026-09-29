@testable import CruftlessCore
import Foundation
import Testing

@Suite("Android discovery edge cases")
struct AndroidDiscoveryEdgeTests {
    @Test("Colon separated Studio system paths are discovered and protected")
    func colonSeparatedSystemPath() throws {
        let home = try makeHome()
        defer { TestFileSystem.removeDirectoryRecursively(at: home) }
        let config = home.appendingPathComponent("Library/Application Support/Google/AndroidStudio2025.1", isDirectory: true)
        let redirected = home.appendingPathComponent("separate-studio-system", isDirectory: true)
        try FileManager.default.createDirectory(at: config, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: redirected, withIntermediateDirectories: true)
        try "idea.system.path: \(redirected.path)\n"
            .write(to: config.appendingPathComponent("idea.properties"), atomically: true, encoding: .utf8)

        #expect(RootResolver.androidStudioSystemIssue(home: home) != nil)
        let policy = ProtectedPaths(customProtectedPaths: [], home: home)
        #expect(policy.isProtected(redirected))
    }

    @Test("Studio cache version enumeration reports its cap")
    func studioCacheLimitIsVisible() throws {
        let home = try makeHome()
        defer { TestFileSystem.removeDirectoryRecursively(at: home) }
        let parent = home.appendingPathComponent("Library/Caches/Google", isDirectory: true)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
        for version in 1...33 {
            let root = parent.appendingPathComponent("AndroidStudio2025.\(version)", isDirectory: true)
            try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        }

        #expect(RootResolver.androidStudioSystemRoots(home: home).count == 32)
        #expect(RootResolver.androidStudioSystemIssue(home: home)?.contains("Too many") == true)
    }

    @Test("SDK source properties identify installed package metadata")
    func sdkPackageMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-package-\(UUID().uuidString)", isDirectory: true)
        let directory = root.appendingPathComponent("platforms/android-35", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        try "Pkg.Desc: Android SDK Platform 35\nPkg.Path=platforms;android-35\nPkg.Revision = 2\n"
            .write(to: directory.appendingPathComponent("source.properties"), atomically: true, encoding: .utf8)

        let package = try #require(RootResolver.androidSDKPackage(at: directory))

        #expect(package.displayName == "Android SDK Platform 35")
        #expect(package.packagePath == "platforms;android-35")
        #expect(package.revision == "2")

        let location = TrackedLocation(
            id: "androidSDK",
            platform: .android,
            title: "Android SDK",
            icon: .symbol("shippingbox"),
            tier: .info,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            mutationPolicy: .readOnly,
            resolveRoots: { [root] }
        )
        let entries = DrillDownProvider.loadChildren(for: location)
        #expect(entries.count == 1)
        #expect(entries.first?.name.contains("Android SDK Platform 35") == true)
    }

    @Test("AVD registry rows resolve to per-device data directories")
    func avdRegistryInventory() throws {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cruftless-avd-inventory-\(UUID().uuidString)", isDirectory: true)
        let root = home.appendingPathComponent(".android/avd", isDirectory: true)
        let device = root.appendingPathComponent("Pixel.avd", isDirectory: true)
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: home) }
        try "avd.ini.displayname=Pixel 8\npath=\(device.path)\npath.rel=avd/Pixel.avd\ntarget=android-35\n"
            .write(to: root.appendingPathComponent("Pixel.ini"), atomically: true, encoding: .utf8)
        try "hw.device.name=Pixel 8\nimage.sysdir.1=system-images/android-35/google_apis/arm64-v8a/\n"
            .write(to: device.appendingPathComponent("config.ini"), atomically: true, encoding: .utf8)

        let item = try #require(RootResolver.androidAVDInventory(roots: [root]).first)

        #expect(item.displayName == "Pixel 8")
        #expect(item.directory == device)
        #expect(item.systemImage == "android-35")

        let location = TrackedLocation(
            id: "androidAVDs",
            platform: .android,
            title: "Android Virtual Devices",
            icon: .symbol("iphone"),
            tier: .info,
            hasDrillDown: true,
            stalenessSource: .topLevelMtime,
            mutationPolicy: .readOnly,
            resolveRoots: { [root] }
        )
        let entries = DrillDownProvider.loadChildren(for: location)
        #expect(entries.count == 1)
        #expect(entries.first?.name == "Pixel 8 · Pixel.ini · android-35")
        #expect(entries.first?.url == device)
    }

    @Test("SDK discovery leaves unsupported nested contents unclassified without a depth warning")
    func sdkUnsupportedLayoutAndRemainder() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-depth-\(UUID().uuidString)", isDirectory: true)
        var nested = root
        for index in 0..<8 {
            nested.appendPathComponent("level-\(index)", isDirectory: true)
        }
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 128).write(to: nested.appendingPathComponent("unknown.bin"))
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let total = DirectoryWalker.walk(url: root, inodeSet: InodeSet()).allocatedBytes
        let result = DrillDownProvider.androidSDKPackages(
            in: [root],
            rootSizes: [RootSize(url: root, allocatedBytes: total)]
        )

        #expect(!(result.issue?.contains("depth limit") ?? false))
        #expect(result.issue?.contains("supported package layouts") == true)
        #expect(result.children.contains { $0.name == "Unclassified SDK contents" })
        #expect(result.children.reduce(Int64(0)) { $0 + $1.reclaimableBytes } == total)
    }

    @Test("Expected SDK support directories remain unclassified without an incomplete notice")
    func sdkAncillaryDirectoriesAreExpected() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-ancillary-\(UUID().uuidString)", isDirectory: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let package = root.appendingPathComponent("platforms/android-36", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        let metadata = """
        <repository>
          <localPackage path="platforms;android-36">
            <display-name>Android 36</display-name>
          </localPackage>
        </repository>
        """
        try metadata.write(to: package.appendingPathComponent("package.xml"), atomically: true, encoding: .utf8)
        for path in ["licenses/android-sdk-license", "skins/pixel/config.ini", "fonts/Roboto.ttf"] {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(repeating: 1, count: 64).write(to: file)
        }

        let total = DirectoryWalker.walk(url: root, inodeSet: InodeSet()).allocatedBytes
        let result = DrillDownProvider.androidSDKPackages(in: [root], rootSizes: [RootSize(url: root, allocatedBytes: total)])

        #expect(result.issue == nil)
        #expect(result.children.contains { $0.name == "Unclassified SDK contents" && $0.reclaimableBytes > 0 })
    }

    @Test("SDK package XML identifies package roots without source properties identity")
    func sdkPackageXMLIdentity() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-xml-\(UUID().uuidString)", isDirectory: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let locations = [
            ("platform-tools", "platform-tools", "Android SDK Platform-Tools", "37.0.1"),
            ("cmdline-tools/latest", "cmdline-tools;latest", "Android SDK Command-line Tools", "19.0"),
            ("build-tools/36.0.0", "build-tools;36.0.0", "Android SDK Build-Tools 36", "36.0.0"),
            ("sources/android-36", "sources;android-36", "Sources for Android 36", "1")
        ]
        for (relative, identity, displayName, revision) in locations {
            let package = root.appendingPathComponent(relative, isDirectory: true)
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            let xml = """
            <?xml version="1.0"?>
            <repository>
              <localPackage path="\(identity)">
                <revision><major>\(revision.split(separator: ".").first ?? "1")</major></revision>
                <display-name>\(displayName)</display-name>
              </localPackage>
            </repository>
            """
            try xml.write(to: package.appendingPathComponent("package.xml"), atomically: true, encoding: .utf8)
            try "Pkg.Revision=\(revision)\n"
                .write(to: package.appendingPathComponent("source.properties"), atomically: true, encoding: .utf8)
            try Data(repeating: 1, count: 64).write(to: package.appendingPathComponent("content.bin"))
        }

        let total = DirectoryWalker.walk(url: root, inodeSet: InodeSet()).allocatedBytes
        let result = DrillDownProvider.androidSDKPackages(in: [root], rootSizes: [RootSize(url: root, allocatedBytes: total)])

        #expect(result.children.filter { $0.id.hasPrefix("androidSDK-") && !$0.id.contains("unclassified") }.count == 4)
        #expect(result.children.contains { $0.name.contains("Android SDK Platform-Tools") })
        #expect(result.children.contains { $0.name.contains("Android SDK Command-line Tools") })
        #expect(result.children.contains { $0.name.contains("Sources for Android 36") })
        #expect(!(result.issue?.contains("depth limit") ?? false))
    }

    @Test("SDK package XML rejects mismatched identities and external entity declarations")
    func sdkPackageXMLRejectsUnsafeMetadata() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-invalid-xml-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("platform-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let xml = """
        <!DOCTYPE repository [<!ENTITY external SYSTEM "file:///etc/passwd">]>
        <repository><localPackage path="wrong"><display-name>&external;</display-name></localPackage></repository>
        """
        try xml.write(to: package.appendingPathComponent("package.xml"), atomically: true, encoding: .utf8)
        try Data(repeating: 1, count: 32).write(to: package.appendingPathComponent("content.bin"))

        let result = DrillDownProvider.androidSDKPackages(in: [root])

        #expect(result.children.isEmpty)
        #expect(result.issue?.contains("malformed or does not match") == true)
    }

    @Test("Malformed SDK package metadata is visible as incomplete inventory")
    func malformedSDKMetadataIsVisible() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-malformed-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("platforms/android-35", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        try String(repeating: "x", count: 65 * 1024)
            .write(to: package.appendingPathComponent("source.properties"), atomically: true, encoding: .utf8)
        let xmlPackage = root.appendingPathComponent("platform-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: xmlPackage, withIntermediateDirectories: true)
        try Data(repeating: 60, count: 65 * 1024).write(to: xmlPackage.appendingPathComponent("package.xml"))
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }

        let result = DrillDownProvider.androidSDKPackages(in: [root])

        #expect(result.issue?.contains("metadata") == true)
    }

    @Test("SDK package XML symlinks are not followed")
    func sdkPackageXMLSymlinkIsIgnored() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("android-sdk-package-link-\(UUID().uuidString)", isDirectory: true)
        let package = root.appendingPathComponent("platform-tools", isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        let outside = root.appendingPathComponent("outside.xml")
        try "<repository><localPackage path=\"platform-tools\"/></repository>"
            .write(to: outside, atomically: true, encoding: .utf8)
        try FileManager.default.createSymbolicLink(at: package.appendingPathComponent("package.xml"), withDestinationURL: outside)

        let result = DrillDownProvider.androidSDKPackages(in: [root])

        #expect(result.children.isEmpty)
        #expect(result.issue?.contains("malformed or does not match") == true)
    }

    @Test("Two AVD registry entries for one data directory are reported as ambiguous")
    func duplicateAVDDirectoryIsIncomplete() throws {
        let home = try makeHome()
        defer { TestFileSystem.removeDirectoryRecursively(at: home) }
        let root = home.appendingPathComponent(".android/avd", isDirectory: true)
        let device = root.appendingPathComponent("Pixel.avd", isDirectory: true)
        try FileManager.default.createDirectory(at: device, withIntermediateDirectories: true)
        for name in ["Pixel.ini", "Alias.ini"] {
            try "path=\(device.path)\n"
                .write(to: root.appendingPathComponent(name), atomically: true, encoding: .utf8)
        }

        #expect(RootResolver.androidAVDMetadataIssue(root: root, home: home)?.contains("same data directory") == true)
        #expect(RootResolver.androidAVDInventory(roots: [root]).count == 2)
    }

    private func makeHome() throws -> URL {
        let home = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".cruftless-android-discovery-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }
}
