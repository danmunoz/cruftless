@testable import CruftlessCore
import Foundation
import ServiceManagement
import Testing

@Suite("Launch at login messages")
struct LaunchAtLoginPolicyTests {
    @Test("Enabling into .requiresApproval reports the approval step, not success")
    func requiresApprovalIsReported() {
        let message = LaunchAtLoginPolicy.message(requested: true, status: .requiresApproval, failure: nil)
        #expect(message?.contains("Login Items") == true)
    }

    @Test("Enabling that actually landed reports nothing")
    func enabledIsSilent() {
        #expect(LaunchAtLoginPolicy.message(requested: true, status: .enabled) == nil)
    }

    @Test("A missing login item names the fix")
    func notFound() {
        let message = LaunchAtLoginPolicy.message(requested: true, status: .notFound)
        #expect(message?.contains("Applications") == true)
    }

    @Test("A thrown failure is surfaced when the status says nothing more specific")
    func thrownFailureSurfaces() {
        let message = LaunchAtLoginPolicy.message(
            requested: true,
            status: .notRegistered,
            failure: "Operation not permitted"
        )
        #expect(message == "Operation not permitted")
    }

    @Test("Disabling something already off is not an error, even when it threw")
    func disableThatThrewButReachedGoalState() {
        #expect(LaunchAtLoginPolicy.message(requested: false, status: .notRegistered, failure: "boom") == nil)
    }

    @Test("Disabling that left the item enabled is an error")
    func disableThatFailed() {
        #expect(LaunchAtLoginPolicy.message(requested: false, status: .enabled, failure: nil) != nil)
    }
}

@Suite("Protected path admission")
struct ProtectedPathPolicyTests {
    private let home = URL(fileURLWithPath: "/Users/tester", isDirectory: true)

    @Test("The volume root is refused")
    func volumeRoot() {
        #expect(
            ProtectedPathPolicy.rejection(for: URL(fileURLWithPath: "/"), home: home) == .volumeRoot
        )
    }

    @Test("The home directory is refused: it is already protected")
    func homeDirectory() {
        #expect(ProtectedPathPolicy.rejection(for: home, home: home) == .homeDirectory)
    }

    @Test("A folder under an entry already listed is refused as redundant")
    func nestedUnderExisting() {
        let existing = [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Dev/App", isDirectory: true),
            home: home,
            existing: existing
        )
        #expect(rejection == .alreadyCovered(ancestor: "~/Dev"))
    }

    @Test("A sibling sharing a name prefix is not treated as nested")
    func siblingPrefixIsNotNested() {
        let existing = [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Development", isDirectory: true),
            home: home,
            existing: existing
        )
        #expect(rejection == nil)
    }

    @Test("An unrelated folder is admitted")
    func admitted() {
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Archive", isDirectory: true),
            home: home,
            existing: [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        )
        #expect(rejection == nil)
    }

    @Test("A trailing slash does not disguise a duplicate")
    func trailingSlashDuplicate() {
        let existing = [URL(fileURLWithPath: "/Users/tester/Dev", isDirectory: true)]
        let rejection = ProtectedPathPolicy.rejection(
            for: URL(fileURLWithPath: "/Users/tester/Dev/", isDirectory: true),
            home: home,
            existing: existing
        )
        #expect(rejection == .alreadyCovered(ancestor: "~/Dev"))
    }
}

@Suite("Version display")
struct CruftlessVersionTests {
    @Test("Short version and build render together")
    func shortAndBuild() {
        #expect(CruftlessVersion.display(shortVersion: "1.2", build: "34") == "Version 1.2 (34)")
    }

    @Test("A build that duplicates the short version is not repeated")
    func duplicateBuild() {
        #expect(CruftlessVersion.display(shortVersion: "1.0", build: "1.0") == "Version 1.0")
    }

    @Test("A missing build still renders a version")
    func missingBuild() {
        #expect(CruftlessVersion.display(shortVersion: "1.0", build: nil) == "Version 1.0")
        #expect(CruftlessVersion.display(shortVersion: "1.0", build: "  ") == "Version 1.0")
    }

    @Test("A bundle carrying neither key renders nothing")
    func nothingToShow() {
        #expect(CruftlessVersion.display(shortVersion: nil, build: nil) == nil)
    }
}
