import CruftlessFixtures
import Foundation
import Testing

@Suite("Scratch defaults")
struct ScratchDefaultsTests {
    private var preferencesDirectory: String {
        NSHomeDirectory() + "/Library/Preferences"
    }

    @Test("A scratch suite stores its plist in the temporary directory, not Preferences")
    func storesOutsidePreferences() throws {
        let scratch = ScratchDefaults()
        defer { TestFileSystem.remove(scratch) }
        scratch.defaults.set("value", forKey: "key")
        CFPreferencesAppSynchronize(scratch.suiteName as CFString)

        #expect(scratch.fileURL.path(percentEncoded: false).hasPrefix(NSTemporaryDirectory()))
        #expect(FileManager.default.fileExists(atPath: scratch.fileURL.path(percentEncoded: false)))
        let leaf = scratch.fileURL.lastPathComponent
        let preferences = try FileManager.default.contentsOfDirectory(atPath: preferencesDirectory)
        #expect(!preferences.contains(leaf))
    }

    @Test("A second instance on the same suite reads what the first wrote")
    func sharesValuesAcrossInstances() throws {
        let scratch = ScratchDefaults()
        defer { TestFileSystem.remove(scratch) }
        scratch.defaults.set("value", forKey: "key")

        let reopened = try #require(UserDefaults(suiteName: scratch.suiteName))
        #expect(reopened.string(forKey: "key") == "value")
    }

    @Test("Removing a scratch suite leaves no plist behind")
    func removeDeletesTheFile() async throws {
        let scratch = ScratchDefaults()
        scratch.defaults.set("value", forKey: "key")
        CFPreferencesAppSynchronize(scratch.suiteName as CFString)

        TestFileSystem.remove(scratch)
        try await Task.sleep(for: .milliseconds(500))

        #expect(!FileManager.default.fileExists(atPath: scratch.fileURL.path(percentEncoded: false)))
    }
}
