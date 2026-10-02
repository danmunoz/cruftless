@testable import CruftlessCore
import Foundation
import Testing

@Suite("Authoritative SDK metadata diagnostics")
struct AndroidSDKMetadataReaderTests {
    @Test("Readable malformed XML is diagnosed even when properties provide a fallback")
    func malformedXMLFallback() throws {
        try withPackage { root, directory in
            try write("<repository><localPackage", to: directory, name: "package.xml")
            try write("Pkg.Revision=37.0.1\n", to: directory, name: "source.properties")
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package != nil)
            #expect(result.diagnostic?.reason == .malformedXML)
            #expect(result.diagnostic?.packageXMLStatus == .malformed)
            #expect(result.diagnostic?.sourcePropertiesStatus == .valid)
            let scan = DrillDownProvider.androidSDKPackages(in: [root])
            #expect(scan.children.contains { $0.name.contains("37.0.1") })
            #expect(scan.issue == "Some SDK package metadata could not be verified. Unclassified space remains included in the total.")
        }
    }

    @Test("Conflicting XML and properties are refused rather than silently falling back")
    func conflictingMetadata() throws {
        try withPackage { root, directory in
            try write(xml(path: "emulator"), to: directory, name: "package.xml")
            try write("Pkg.Path=platform-tools\nPkg.Revision=37\n", to: directory, name: "source.properties")
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package == nil)
            #expect(result.diagnostic?.reason == .conflictingIdentity)
            #expect(result.diagnostic?.packageXMLStatus == .conflicting)
            #expect(result.diagnostic?.identityMatchesLayout == false)
        }
    }

    @Test("Missing optional properties do not warn for a valid XML-only package")
    func xmlOnlyPackage() throws {
        try withPackage { root, directory in
            try write(xml(path: "platform-tools"), to: directory, name: "package.xml")
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package?.packagePath == "platform-tools")
            #expect(result.diagnostic == nil)
        }
    }

    @Test("Namespace-qualified XML and escaped SDK properties are recognized")
    func namespaceAndPropertiesEscapes() throws {
        try withPackage { root, directory in
            let metadata = """
            <sdk:repository xmlns:sdk="https://example.invalid/sdk">
              <sdk:localPackage path="platform-tools"><sdk:revision><sdk:major>37</sdk:major></sdk:revision></sdk:localPackage>
            </sdk:repository>
            """
            try write(metadata, to: directory, name: "package.xml")
            try write("Pkg.Path=platform\\u002Dtools\nPkg.Revision=3\\\n  7\n", to: directory, name: "source.properties")
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package?.revision == "37")
            #expect(result.diagnostic == nil)
        }
    }

    @Test("Documented latest directory accepts only a coherent version alias")
    func latestAlias() throws {
        try withPackage(relativePath: "cmdline-tools/latest") { root, directory in
            try write(xml(path: "cmdline-tools;19.0", major: "19"), to: directory, name: "package.xml")
            try write("Pkg.Path=cmdline-tools;19.0\nPkg.Revision=19.0\n", to: directory, name: "source.properties")
            #expect(AndroidSDKMetadataReader.read(directory: directory, root: root).diagnostic == nil)
            try write("Pkg.Path=cmdline-tools;18.0\nPkg.Revision=18.0\n", to: directory, name: "source.properties")
            let conflict = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(conflict.package == nil)
            #expect(conflict.diagnostic?.reason == .conflictingIdentity)
        }
    }

    @Test("Oversized metadata is distinguished from malformed text")
    func oversizedMetadata() throws {
        try withPackage { root, directory in
            try write(String(repeating: "x", count: 65537), to: directory, name: "source.properties")
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package == nil)
            #expect(result.diagnostic?.reason == .oversizedMetadata)
            #expect(result.diagnostic?.sourcePropertiesStatus == .tooLarge)
        }
    }

    @Test("Metadata links are not normalized into valid files")
    func metadataSymlink() throws {
        try withPackage { root, directory in
            let outside = root.appendingPathComponent("outside.xml")
            try xml(path: "platform-tools").write(to: outside, atomically: true, encoding: .utf8)
            try FileManager.default.createSymbolicLink(at: directory.appendingPathComponent("package.xml"), withDestinationURL: outside)
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package == nil)
            #expect(result.diagnostic?.reason == .symlinkMetadata)
            #expect(result.diagnostic?.packageXMLStatus == .symlink)
        }
    }

    @Test("UTF-16 entity declarations are rejected before XML parsing")
    func utf16EntityDeclaration() throws {
        try withPackage { root, directory in
            let text = "<!DOCTYPE repository [<!ENTITY sample 'private'>]>" + xml(path: "platform-tools")
            try #require(text.data(using: .utf16)).write(to: directory.appendingPathComponent("package.xml"))
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.package == nil)
            #expect(result.diagnostic?.reason == .invalidEncoding)
        }
    }

    @Test("UTF-8 entity declarations are rejected even alongside valid properties")
    func entityDeclarationFallback() throws {
        try withPackage { root, directory in
            try write("<!DOCTYPE repository [<!ENTITY sample 'private'>]>" + xml(path: "platform-tools"),
                      to: directory, name: "package.xml")
            try write("Pkg.Revision=37\n", to: directory, name: "source.properties")
            let result = AndroidSDKMetadataReader.read(directory: directory, root: root)
            #expect(result.diagnostic?.reason == .malformedXML)
            #expect(result.diagnostic?.packageXMLStatus == .malformed)
        }
    }

    @Test("Non-regular metadata does not block the reader")
    func directoryMetadata() throws {
        try withPackage { root, directory in
            try FileManager.default.createDirectory(at: directory.appendingPathComponent("package.xml"), withIntermediateDirectories: true)
            #expect(AndroidSDKMetadataReader.read(directory: directory, root: root).diagnostic?.reason == .nonRegularMetadata)
        }
    }

    @Test("Unresolved bytes stay counted and diagnostic order is bounded and deterministic")
    func discoveryAccountingAndBounds() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sdk-diagnostic-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        for index in (0 ..< 132).reversed() {
            let package = root.appendingPathComponent("platforms/android-\(String(format: "%03d", index))")
            try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
            try write("<repository>", to: package, name: "package.xml")
        }
        let total = DirectoryWalker.walk(url: root, inodeSet: InodeSet()).allocatedBytes
        let result = DrillDownProvider.androidSDKPackages(in: [root], rootSizes: [RootSize(url: root, allocatedBytes: total)])
        #expect(result.diagnosticCount == 132)
        #expect(result.diagnostics.count == 128)
        #expect(result.diagnosticsTruncated)
        #expect(result.diagnostics.map(\.relativePath) == result.diagnostics.map(\.relativePath).sorted())
        #expect(result.children.reduce(Int64(0)) { $0 + $1.reclaimableBytes } == total)
        #expect(result.children.first?.name == "Unclassified SDK contents")
    }

    private func withPackage(
        relativePath: String = "platform-tools",
        _ body: (URL, URL) throws -> Void
    ) throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sdk-reader-\(UUID().uuidString)")
        let package = root.appendingPathComponent(relativePath, isDirectory: true)
        try FileManager.default.createDirectory(at: package, withIntermediateDirectories: true)
        defer { TestFileSystem.removeDirectoryRecursively(at: root) }
        try body(root, package)
    }

    private func write(_ value: String, to directory: URL, name: String) throws {
        try value.write(to: directory.appendingPathComponent(name), atomically: true, encoding: .utf8)
    }

    private func xml(path: String, major: String = "37") -> String {
        "<repository><localPackage path=\"\(path)\"><revision><major>\(major)</major></revision></localPackage></repository>"
    }
}
