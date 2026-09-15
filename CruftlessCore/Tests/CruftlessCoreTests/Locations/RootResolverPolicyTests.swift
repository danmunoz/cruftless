import CruftlessCore
import Foundation
import Testing

@Suite("RootResolver custom-location policy")
struct RootResolverPolicyTests {
    private let key = RootResolver.derivedDataPreferenceKey

    private var home: URL {
        URL(fileURLWithPath: NSHomeDirectory(), isDirectory: true)
    }

    private var fallback: URL {
        RootResolver.defaultDerivedDataRoot(home: home)
    }

    private func resolve(
        _ value: String?,
        protectedPaths: ProtectedPaths = ProtectedPaths(),
        fallback: URL? = nil,
        preferenceKey: String? = nil
    ) -> (root: URL, issue: RootPreferenceIssue?) {
        RootResolver.customRoot(
            preferenceKey: preferenceKey ?? key,
            preference: value,
            fallback: fallback ?? self.fallback,
            policy: .standard(home: home, protectedPaths: protectedPaths)
        )
    }

    @Test("No preference and an empty preference both use the default root")
    func absentPreferenceUsesFallback() {
        for value in [nil, "", "   ", "\n"] as [String?] {
            let outcome = resolve(value)
            #expect(outcome.root == fallback)
            #expect(outcome.issue == nil)
        }
    }

    @Test("A usable absolute location is adopted, normalized")
    func usableLocationAdopted() {
        let outcome = resolve("/Volumes/Ext/DerivedData")
        #expect(ProtectedPaths.normalize(outcome.root) == "/Volumes/Ext/DerivedData")
        #expect(outcome.issue == nil)
    }

    @Test("A tilde path is expanded rather than treated as relative")
    func tildeExpanded() {
        let outcome = resolve("~/Sources/Build/DerivedData")
        let expected = home.appendingPathComponent("Sources/Build/DerivedData", isDirectory: true)
        #expect(ProtectedPaths.normalize(outcome.root) == ProtectedPaths.normalize(expected))
        #expect(outcome.issue == nil)
    }

    @Test(
        "Hostile preference values are refused, with the default root as fallback",
        arguments: [
            ("Build", RootPreferenceIssue.Reason.notAbsolute),
            ("./Build", .notAbsolute),
            ("../../etc", .notAbsolute),
            ("/", .filesystemRoot),
            ("~", .containsHomeFolder),
            ("~/", .containsHomeFolder),
            ("/Volumes", .protectedLocation),
            ("/Volumes/Ext", .protectedLocation),
            ("/Library", .protectedLocation),
            ("/Library/Developer", .protectedLocation),
            ("/etc", .protectedLocation),
            ("/opt/build", .protectedLocation),
            ("/var/db/build", .protectedLocation),
            ("/Users/someoneelse/Build", .protectedLocation),
            ("~/Library", .protectedLocation),
            ("~/Library/Developer", .protectedLocation),
            ("~/Library/Developer/Xcode", .protectedLocation),
            ("~/Library/Developer/Xcode/UserData/Previews", .overlapsTrackedLocation),
            ("~/Library/Developer/Toolchains/Nested", .overlapsTrackedLocation)
        ]
    )
    func hostileValuesRefused(value: String, reason: RootPreferenceIssue.Reason) {
        let outcome = resolve(value)
        #expect(outcome.root == fallback, Comment(rawValue: value))
        #expect(outcome.issue?.reason == reason, Comment(rawValue: value))
        #expect(outcome.issue?.value == value)
        #expect(outcome.issue?.preferenceKey == key)
    }

    @Test("A relative value is never resolved against the working directory")
    func relativeValueNeverResolved() {
        let outcome = resolve("Build")
        #expect(outcome.root == fallback)
        #expect(!ProtectedPaths.normalize(outcome.root).hasSuffix("/Build"))
    }

    @Test("A value equal to the location's own default is adopted without an issue")
    func defaultValueIsNotAnOverlap() {
        let outcome = resolve(fallback.path(percentEncoded: false))
        #expect(ProtectedPaths.normalize(outcome.root) == ProtectedPaths.normalize(fallback))
        #expect(outcome.issue == nil)
    }

    @Test("A user-protected folder is not adopted as a custom root")
    func userProtectedFolderRefused() {
        let protectedFolder = URL(fileURLWithPath: "/Volumes/Ext/Sacred", isDirectory: true)
        let outcome = resolve(
            "/Volumes/Ext/Sacred/DerivedData",
            protectedPaths: ProtectedPaths(customProtectedPaths: [protectedFolder])
        )
        #expect(outcome.root == fallback)
        #expect(outcome.issue?.reason == .protectedLocation)
    }

    @Test("The archives key is judged by the same policy")
    func archivesKeyUsesSamePolicy() {
        let archivesFallback = RootResolver.defaultArchivesRoot(home: home)
        let outcome = resolve(
            "~",
            fallback: archivesFallback,
            preferenceKey: RootResolver.archivesPreferenceKey
        )
        #expect(outcome.root == archivesFallback)
        #expect(outcome.issue?.preferenceKey == "IDECustomDistributionArchivesLocation")
        #expect(outcome.issue?.reason == .containsHomeFolder)
    }

    @Test("Every refusal carries copy naming the key, the value, and the reason")
    func issueMessageIsShowable() {
        for reason in RootPreferenceIssue.Reason.allCases {
            let issue = RootPreferenceIssue(preferenceKey: key, value: "/somewhere", reason: reason)
            #expect(issue.message.contains(key))
            #expect(issue.message.contains("/somewhere"))
            #expect(issue.message.contains("default location"))
        }
    }

    @Test("An adopted custom root is usable by the guard")
    func adoptedRootIsUsable() throws {
        let outcome = resolve("/Volumes/Ext/DerivedData")
        let guardInstance = PathGuard(roots: [outcome.root])
        #expect(guardInstance.roots.count == 1)
        let child = outcome.root.appendingPathComponent("MyApp-abc", isDirectory: true)
        #expect(try guardInstance.validate(child).path == ProtectedPaths.normalize(child))
    }

    @Test("Live derived-data and archives roots are always usable roots")
    func liveRootsAreUsable() {
        let policy = ProtectedPaths()
        for root in RootResolver.derivedDataRoots() + RootResolver.archivesRoot() {
            #expect(policy.isUsableRoot(root), "\(root.path)")
        }
    }
}
