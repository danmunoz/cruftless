import CruftlessCore
import Foundation
import Testing

@Suite("ActiveToolchain")
struct ActiveToolchainTests {
    private func withDefaults(_ body: (UserDefaults) throws -> Void) throws {
        let suiteName = "cruftless.tests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        try body(defaults)
    }

    private func makeToolchain(identifier: String?, named name: String = "swift-DEVELOPMENT") throws -> URL {
        let base = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let toolchain = base.appendingPathComponent("\(name).xctoolchain", isDirectory: true)
        try FileManager.default.createDirectory(at: toolchain, withIntermediateDirectories: true)
        if let identifier {
            let plist: [String: Any] = ["CFBundleIdentifier": identifier]
            let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .xml, options: 0)
            try data.write(to: toolchain.appendingPathComponent("Info.plist"))
        }
        return toolchain
    }

    @Test("overrideIdentifier reads the DVTDefaultToolchainOverrideIdentifer key")
    func overrideIdentifierReadsKey() throws {
        try withDefaults { defaults in
            #expect(ActiveToolchain.overrideIdentifier(defaults: defaults) == nil)

            defaults.set("org.swift.62202603021a", forKey: "DVTDefaultToolchainOverrideIdentifer")
            #expect(ActiveToolchain.overrideIdentifier(defaults: defaults) == "org.swift.62202603021a")
        }
    }

    @Test("overrideIdentifier treats a blank value as unset")
    func overrideIdentifierTreatsBlankAsUnset() throws {
        try withDefaults { defaults in
            defaults.set("   ", forKey: "DVTDefaultToolchainOverrideIdentifer")
            #expect(ActiveToolchain.overrideIdentifier(defaults: defaults) == nil)
        }
    }

    @Test("identifier(ofToolchainAt:) reads CFBundleIdentifier from Info.plist")
    func identifierReadsInfoPlist() throws {
        let toolchain = try makeToolchain(identifier: "org.swift.62202603021a")
        defer { TestFileSystem.removeDirectoryRecursively(at: toolchain.deletingLastPathComponent()) }

        #expect(ActiveToolchain.identifier(ofToolchainAt: toolchain) == "org.swift.62202603021a")
    }

    @Test("identifier(ofToolchainAt:) returns nil when Info.plist is missing")
    func identifierReturnsNilWithoutInfoPlist() throws {
        let toolchain = try makeToolchain(identifier: nil)
        defer { TestFileSystem.removeDirectoryRecursively(at: toolchain.deletingLastPathComponent()) }

        #expect(ActiveToolchain.identifier(ofToolchainAt: toolchain) == nil)
    }

    @Test("isActive is true only when the bundle's identifier matches the override")
    func isActiveMatchesIdentifier() throws {
        let active = try makeToolchain(identifier: "org.swift.62202603021a", named: "Active")
        let other = try makeToolchain(identifier: "org.swift.other", named: "Other")
        defer {
            TestFileSystem.removeDirectoryRecursively(at: active.deletingLastPathComponent())
            TestFileSystem.removeDirectoryRecursively(at: other.deletingLastPathComponent())
        }

        #expect(ActiveToolchain.isActive(active, overrideIdentifier: "org.swift.62202603021a"))
        #expect(!ActiveToolchain.isActive(other, overrideIdentifier: "org.swift.62202603021a"))
        #expect(!ActiveToolchain.isActive(active, overrideIdentifier: nil))
    }
}
