import CruftlessCore
import Foundation
import Testing

@Suite("RescanThrottle Tests")
struct RescanThrottleTests {
    private let catalog = ["derivedData", "archives", "simulatorDevices"]
    private let start = Date(timeIntervalSince1970: 1_000_000)

    @Test("A location that has never been scanned is admitted immediately")
    func admitsFirstRequest() {
        var throttle = RescanThrottle(interval: 60)

        let admitted = throttle.admit(.locations(["derivedData"]), at: start, catalog: catalog)

        #expect(admitted == .locations(["derivedData"]))
        #expect(throttle.nextWake == nil)
    }

    @Test("A rescan inside the quiet period is held, not run")
    func holdsInsideQuietPeriod() {
        var throttle = RescanThrottle(interval: 60)
        throttle.recordCompletion(of: ["derivedData"], at: start)

        let admitted = throttle.admit(
            .locations(["derivedData"]),
            at: start.addingTimeInterval(3),
            catalog: catalog
        )

        #expect(admitted == nil)
        #expect(throttle.nextWake == start.addingTimeInterval(60))
    }

    @Test("Held work is released once the quiet period ends, never dropped")
    func releasesWhenDue() {
        var throttle = RescanThrottle(interval: 60)
        throttle.recordCompletion(of: ["derivedData"], at: start)
        _ = throttle.admit(.locations(["derivedData"]), at: start.addingTimeInterval(3), catalog: catalog)

        #expect(throttle.release(at: start.addingTimeInterval(59)) == nil)
        #expect(throttle.release(at: start.addingTimeInterval(60)) == .locations(["derivedData"]))
        #expect(throttle.release(at: start.addingTimeInterval(61)) == nil)
        #expect(throttle.nextWake == nil)
    }

    @Test("A rescan after the quiet period runs straight away")
    func admitsAfterQuietPeriod() {
        var throttle = RescanThrottle(interval: 60)
        throttle.recordCompletion(of: ["derivedData"], at: start)

        let admitted = throttle.admit(
            .locations(["derivedData"]),
            at: start.addingTimeInterval(61),
            catalog: catalog
        )

        #expect(admitted == .locations(["derivedData"]))
    }

    @Test("A noisy location does not hold a quiet one back")
    func noisyLocationDoesNotBlockQuietOne() {
        var throttle = RescanThrottle(interval: 60)
        throttle.recordCompletion(of: ["derivedData"], at: start)

        let admitted = throttle.admit(
            .locations(["derivedData", "simulatorDevices"]),
            at: start.addingTimeInterval(3),
            catalog: catalog
        )

        #expect(admitted == .locations(["simulatorDevices"]))
        #expect(throttle.nextWake == start.addingTimeInterval(60))
        #expect(throttle.release(at: start.addingTimeInterval(60)) == .locations(["derivedData"]))
    }

    @Test("A full rescan with nothing held stays a full rescan")
    func everythingStaysWholeWhenNothingHeld() {
        var throttle = RescanThrottle(interval: 60)

        #expect(throttle.admit(.everything, at: start, catalog: catalog) == .everything)
    }

    @Test("A full rescan with one location held degrades to the rest")
    func everythingDegradesWhenPartlyHeld() {
        var throttle = RescanThrottle(interval: 60)
        throttle.recordCompletion(of: ["archives"], at: start)

        let admitted = throttle.admit(.everything, at: start.addingTimeInterval(10), catalog: catalog)

        #expect(admitted == .locations(["derivedData", "simulatorDevices"]))
        #expect(throttle.release(at: start.addingTimeInterval(60)) == .locations(["archives"]))
    }

    @Test("A continuous stream of events cannot chain rescans back to back")
    func continuousEventsCannotChain() {
        var throttle = RescanThrottle(interval: 60)
        var scans = 0
        var now = start

        for _ in 0 ..< 25 {
            if let scope = throttle.admit(.locations(["derivedData"]), at: now, catalog: catalog) {
                scans += 1
                throttle.recordCompletion(of: scope.locationIds(in: catalog), at: now)
            }
            now = now.addingTimeInterval(3)
        }

        #expect(scans == 2)
    }
}

private extension InvalidationScope {
    func locationIds(in catalog: [String]) -> Set<String> {
        switch self {
        case .everything: Set(catalog)
        case let .locations(ids): ids
        }
    }
}
