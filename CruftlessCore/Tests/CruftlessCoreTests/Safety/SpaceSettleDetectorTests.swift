import CruftlessCore
import Foundation
import Testing

@Suite("SpaceSettleDetector Tests")
struct SpaceSettleDetectorTests {
    private static let baseline: Int64 = 100_000_000_000
    private static let fourGigabytes: Int64 = 4_000_000_000

    @Test("A flat plateau never settles before the cap")
    func plateauNeverSettlesBeforeCap() {
        let cap = SpaceSettleDetector.capSamples(forExpectedBytes: Self.fourGigabytes)
        var detector = SpaceSettleDetector(
            expectedBytes: Self.fourGigabytes,
            baselineFreeBytes: Self.baseline
        )

        for sample in 1 ..< cap {
            let observation = detector.observe(freeBytes: Self.baseline)
            #expect(observation == .keepWaiting, "sample \(sample) settled on a plateau")
        }

        #expect(detector.observe(freeBytes: Self.baseline) == .capped)
    }

    @Test("Space that arrives at once settles after five quiet samples")
    func immediateArrivalSettlesAfterQuietWindow() {
        var detector = SpaceSettleDetector(
            expectedBytes: Self.fourGigabytes,
            baselineFreeBytes: Self.baseline
        )

        #expect(detector.observe(freeBytes: Self.baseline) == .keepWaiting)
        for sample in 2 ... 6 {
            let observation = detector.observe(freeBytes: Self.baseline + Self.fourGigabytes)
            #expect(observation == .keepWaiting, "settled early at sample \(sample)")
        }

        #expect(detector.observe(freeBytes: Self.baseline + Self.fourGigabytes) == .settled)
    }

    @Test("A delta larger than the tolerance restarts the quiet window")
    func oversizeDeltaRestartsQuietWindow() {
        let spike = Self.baseline + Self.fourGigabytes + 100_000_000
        var detector = SpaceSettleDetector(
            expectedBytes: Self.fourGigabytes,
            baselineFreeBytes: Self.baseline
        )

        _ = detector.observe(freeBytes: Self.baseline)
        for _ in 1 ... 4 {
            _ = detector.observe(freeBytes: Self.baseline + Self.fourGigabytes)
        }

        #expect(detector.observe(freeBytes: spike) == .keepWaiting)

        for sample in 7 ... 10 {
            let observation = detector.observe(freeBytes: spike)
            #expect(observation == .keepWaiting, "settled at sample \(sample)")
        }

        #expect(detector.observe(freeBytes: spike) == .settled)
    }

    @Test("Arrival below ninety percent caps even while quiet")
    func belowNinetyPercentCaps() {
        let cap = SpaceSettleDetector.capSamples(forExpectedBytes: Self.fourGigabytes)
        let eightySevenPercent = Self.baseline + 3_500_000_000
        var detector = SpaceSettleDetector(
            expectedBytes: Self.fourGigabytes,
            baselineFreeBytes: Self.baseline
        )

        for sample in 1 ..< cap {
            let observation = detector.observe(freeBytes: eightySevenPercent)
            #expect(observation == .keepWaiting, "sample \(sample) settled below the arrival threshold")
        }

        #expect(detector.observe(freeBytes: eightySevenPercent) == .capped)
    }

    @Test("A capped settle carries the note and a settled one does not")
    func cappedSettleCarriesNote() {
        #expect(SpaceSettleOutcome.capped.note == "Free space was still arriving when the result was measured.")
        #expect(SpaceSettleOutcome.settled.note == nil)
    }

    @Test("The cap grows with the expected size and floors at sixty samples")
    func capGrowsWithExpectedBytes() {
        #expect(SpaceSettleDetector.capSamples(forExpectedBytes: 1000) == 60)
        #expect(SpaceSettleDetector.capSamples(forExpectedBytes: 4_350_000_000) == 60)
        #expect(SpaceSettleDetector.capSamples(forExpectedBytes: 20_000_000_000) == 190)
    }
}
