@testable import CruftlessCore
import Foundation
import Testing

@Suite("Xcode install discovery")
struct XcodeInstallDiscoveryTests {
    @Test("Only absolute .app paths survive parsing")
    func parseFiltersNoise() {
        let output = """
        /Applications/Xcode.app
          /Applications/Xcode-beta.app
        mdfind: some warning
        relative/Xcode.app

        /Users/dan/Downloads/Xcode.app.zip
        /Volumes/Ext/Xcode 26.app
        """
        let parsed = XcodeInstallDiscovery.parse(output).map { $0.path(percentEncoded: false) }
        #expect(parsed == [
            "/Applications/Xcode.app/",
            "/Applications/Xcode-beta.app/",
            "/Volumes/Ext/Xcode 26.app/"
        ])
    }

    @Test("Empty Spotlight output parses to nothing, not to garbage")
    func parseEmpty() {
        #expect(XcodeInstallDiscovery.parse("").isEmpty)
        #expect(XcodeInstallDiscovery.parse("\n\n").isEmpty)
    }

    @Test("The synchronous accessor never blocks on Spotlight")
    func knownInstallsIsImmediate() {
        let clock = ContinuousClock()
        let start = clock.now
        _ = XcodeInstallDiscovery.knownInstalls()
        #expect(clock.now - start < .milliseconds(200))
    }

    @Test("Discovery is cached and concurrent callers share one run")
    func discoverIsIdempotent() async {
        async let first = XcodeInstallDiscovery.discover()
        async let second = XcodeInstallDiscovery.discover()
        let (firstRun, secondRun) = await (first, second)
        #expect(firstRun == secondRun)
        #expect(XcodeInstallDiscovery.knownInstalls() == firstRun)
        #expect(firstRun.allSatisfy { $0.pathExtension == "app" })
    }

    @Test("The minimal environment pins PATH and drops the toolchain overrides")
    func minimalEnvironment() {
        let inherited = [
            "HOME": "/Users/dan",
            "PATH": "/opt/homebrew/bin:/usr/bin",
            "DEVELOPER_DIR": "/Applications/Xcode-beta.app/Contents/Developer",
            "DYLD_INSERT_LIBRARIES": "/tmp/evil.dylib",
            "LANG": "en_US.UTF-8"
        ]
        let environment = BoundedProcess.minimalEnvironment(from: inherited)
        #expect(environment["HOME"] == "/Users/dan")
        #expect(environment["LANG"] == "en_US.UTF-8")
        #expect(environment["PATH"] == "/usr/bin:/bin:/usr/sbin:/sbin")
        #expect(environment["DEVELOPER_DIR"] == nil)
        #expect(environment["DYLD_INSERT_LIBRARIES"] == nil)
    }
}
