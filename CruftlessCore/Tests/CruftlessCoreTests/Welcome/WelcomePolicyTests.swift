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

    @Test("The access step exists only when something needs access")
    func accessStepIsConditional() {
        #expect(WelcomePolicy.steps(hasAccessNeeds: false) == [.location, .safety, .setup])
        #expect(WelcomePolicy.steps(hasAccessNeeds: true) == [.location, .safety, .access, .setup])
    }

    @Test("Stepping forward and back stops at the ends")
    func stepping() {
        let steps = WelcomePolicy.steps(hasAccessNeeds: false)
        #expect(WelcomePolicy.step(after: .location, in: steps) == .safety)
        #expect(WelcomePolicy.step(after: .safety, in: steps) == .setup)
        #expect(WelcomePolicy.step(after: .setup, in: steps) == nil)
        #expect(WelcomePolicy.step(before: .setup, in: steps) == .safety)
        #expect(WelcomePolicy.step(before: .location, in: steps) == nil)
    }

    @Test("A step that leaves the list resolves to the last step")
    func resolvesRemovedStep() {
        let steps = WelcomePolicy.steps(hasAccessNeeds: false)
        #expect(WelcomePolicy.resolved(.access, in: steps) == .setup)
        #expect(WelcomePolicy.resolved(.safety, in: steps) == .safety)
    }

    @Test("The safety promise has three distinct lines")
    func safetyPromises() {
        #expect(WelcomePolicy.safetyPromises.count == 3)
        #expect(Set(WelcomePolicy.safetyPromises.map(\.id)).count == 3)
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
        #expect(detected.note(for: .apple).hasSuffix("Found on this Mac."))
        #expect(detected.note(for: .android).hasSuffix("Not found on this Mac."))
    }
}
