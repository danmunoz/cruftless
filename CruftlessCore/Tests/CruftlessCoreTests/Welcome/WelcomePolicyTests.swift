@testable import CruftlessCore
import Foundation
import Testing

@Suite("Welcome policy")
struct WelcomePolicyTests {
    @Test("Shows only on a first run with no saved scan")
    func showsOnce() {
        #expect(WelcomePolicy.shouldShow(isCompleted: false, hasSavedInventory: false))
        #expect(!WelcomePolicy.shouldShow(isCompleted: true, hasSavedInventory: false))
        #expect(!WelcomePolicy.shouldShow(isCompleted: false, hasSavedInventory: true))
        #expect(!WelcomePolicy.shouldShow(isCompleted: true, hasSavedInventory: true))
    }

    @Test("The access step exists only when something needs access, after the platform choice")
    func accessStepIsConditional() {
        #expect(WelcomePolicy.steps(hasAccessNeeds: false) == [.location, .safety, .setup, .scan])
        #expect(WelcomePolicy.steps(hasAccessNeeds: true) == [.location, .safety, .setup, .access, .scan])
    }

    @Test("Stepping forward and back stops at the ends")
    func stepping() {
        let steps = WelcomePolicy.steps(hasAccessNeeds: false)
        #expect(WelcomePolicy.step(after: .location, in: steps) == .safety)
        #expect(WelcomePolicy.step(after: .safety, in: steps) == .setup)
        #expect(WelcomePolicy.step(after: .setup, in: steps) == .scan)
        #expect(WelcomePolicy.step(after: .scan, in: steps) == nil)
        #expect(WelcomePolicy.step(before: .setup, in: steps) == .safety)
        #expect(WelcomePolicy.step(before: .location, in: steps) == nil)
    }

    @Test("The scan step has no way back")
    func scanStepCannotGoBack() {
        for hasAccessNeeds in [false, true] {
            let steps = WelcomePolicy.steps(hasAccessNeeds: hasAccessNeeds)
            #expect(WelcomePolicy.step(before: .scan, in: steps) == nil)
        }
    }

    @Test("Only the step right before the scan starts it")
    func startsScan() {
        let plain = WelcomePolicy.steps(hasAccessNeeds: false)
        #expect(WelcomePolicy.startsScan(after: .setup, in: plain))
        #expect(!WelcomePolicy.startsScan(after: .safety, in: plain))

        let withAccess = WelcomePolicy.steps(hasAccessNeeds: true)
        #expect(!WelcomePolicy.startsScan(after: .setup, in: withAccess))
        #expect(WelcomePolicy.startsScan(after: .access, in: withAccess))
        #expect(!WelcomePolicy.startsScan(after: .scan, in: withAccess))
    }

    @Test("A step that leaves the list resolves to the step before it, never forward into the scan")
    func resolvesRemovedStep() {
        let steps = WelcomePolicy.steps(hasAccessNeeds: false)
        #expect(WelcomePolicy.resolved(.access, in: steps) == .setup)
        #expect(WelcomePolicy.resolved(.safety, in: steps) == .safety)
        #expect(WelcomePolicy.resolved(.scan, in: steps) == .scan)
    }

    @Test("The safety promise has three distinct lines, one of them the flagged warning")
    func safetyPromises() {
        #expect(WelcomePolicy.safetyPromises.count == 3)
        #expect(Set(WelcomePolicy.safetyPromises.map(\.id)).count == 3)
        #expect(WelcomePolicy.safetyPromises.count(where: \.isWarning) == 1)
        #expect(WelcomePolicy.safetyPromises.allSatisfy { !$0.symbol.isEmpty })
    }
}

@Suite("Platform detection")
struct PlatformDetectionTests {
    private let xcode = URL(fileURLWithPath: "/Applications/Xcode.app", isDirectory: true)
    private let gradle = URL(fileURLWithPath: "/Users/someone/.gradle/caches", isDirectory: true)

    @Test("An Xcode install or Xcode's own folder counts as Apple")
    func appleSignals() {
        #expect(PlatformDetection.detect(xcodeInstalls: [xcode], hasXcodeUserData: false, androidRoots: []).hasApple)
        #expect(PlatformDetection.detect(xcodeInstalls: [], hasXcodeUserData: true, androidRoots: []).hasApple)
        #expect(!PlatformDetection.detect(xcodeInstalls: [], hasXcodeUserData: false, androidRoots: [gradle]).hasApple)
    }

    @Test("Any Android root counts as Android")
    func androidSignals() {
        #expect(PlatformDetection.detect(xcodeInstalls: [], hasXcodeUserData: false, androidRoots: [gradle]).hasAndroid)
        #expect(!PlatformDetection.detect(xcodeInstalls: [xcode], hasXcodeUserData: true, androidRoots: []).hasAndroid)
    }

    @Test("Preselection follows what was found, and nothing found selects everything")
    func selection() {
        #expect(DetectedPlatforms(hasApple: true, hasAndroid: false).selection == .appleOnly)
        #expect(DetectedPlatforms(hasApple: false, hasAndroid: true).selection == .androidOnly)
        #expect(DetectedPlatforms(hasApple: true, hasAndroid: true).selection == .all)
        #expect(DetectedPlatforms(hasApple: false, hasAndroid: false).selection == .all)
    }

    @Test("The note says whether the platform was found")
    func notes() {
        let detected = DetectedPlatforms(hasApple: true, hasAndroid: false)
        #expect(detected.note(for: .apple) == "Xcode, simulators and Swift packages.")
        #expect(detected.note(for: .android) == "Not found on this Mac.")
    }

    @Test("The Apple note counts the Xcode installs found")
    func xcodeInstallCount() {
        let other = URL(fileURLWithPath: "/Applications/Xcode-beta.app", isDirectory: true)
        let one = PlatformDetection.detect(xcodeInstalls: [xcode], hasXcodeUserData: true, androidRoots: [])
        let two = PlatformDetection.detect(xcodeInstalls: [xcode, other], hasXcodeUserData: false, androidRoots: [])
        #expect(one.note(for: .apple).hasPrefix("1 Xcode install,"))
        #expect(two.note(for: .apple).hasPrefix("2 Xcode installs,"))
    }
}
