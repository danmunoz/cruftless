import CruftlessCore
import Foundation
import Testing

@Suite("ScanScheduler")
struct ScanSchedulerTests {
    private static let catalog: Set<String> = ["derivedData", "archives", "simulatorDevices"]
    private static let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    private static let running = ScanConditions(hasStartedInitialScan: true, isDeleting: false)

    private static func background(_ ids: Set<String>) -> ScanRequest {
        ScanRequest(scope: .locations(ids), trigger: .background)
    }

    private static let userEverything = ScanRequest(scope: .everything, trigger: .user)

    @Test("A background request before the session's first scan starts nothing")
    func backgroundBeforeInitialScanIsDeclined() {
        var scheduler = ScanScheduler()
        let launching = ScanConditions(hasStartedInitialScan: false, isDeleting: false)

        let admission = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: launching)

        #expect(admission == .declined)
        #expect(scheduler.active == nil)
        #expect(scheduler.pending == nil)
        #expect(scheduler.nextWake == nil)
    }

    @Test("A user request before the first scan starts straight away")
    func userBeforeInitialScanStarts() {
        var scheduler = ScanScheduler()
        let launching = ScanConditions(hasStartedInitialScan: false, isDeleting: false)

        let admission = scheduler.request(Self.userEverything, at: Self.now, catalog: Self.catalog, conditions: launching)

        #expect(admission == .start(Self.userEverything))
    }

    @Test("A background request during a deletion waits for it to end")
    func backgroundDuringDeletionIsDeferred() {
        var scheduler = ScanScheduler()
        let deleting = ScanConditions(hasStartedInitialScan: true, isDeleting: true)
        let request = Self.background(["derivedData"])

        #expect(scheduler.request(request, at: Self.now, catalog: Self.catalog, conditions: deleting) == .queued(request))
        #expect(scheduler.active == nil)
        #expect(scheduler.resume(at: Self.now, catalog: Self.catalog, conditions: deleting) == .queued(request))
        #expect(scheduler.resume(at: Self.now, catalog: Self.catalog, conditions: Self.running) == .start(request))
    }

    @Test("The rescan after a deletion runs while the deletion is still finishing")
    func userDuringDeletionStarts() {
        var scheduler = ScanScheduler()
        let deleting = ScanConditions(hasStartedInitialScan: true, isDeleting: true)
        let request = ScanRequest(scope: .locations(["derivedData"]), trigger: .user)

        #expect(scheduler.request(request, at: Self.now, catalog: Self.catalog, conditions: deleting) == .start(request))
    }

    @Test("Requests behind a running scan merge, and a user one marks the running scan as watched")
    func busyRequestsMergeAndUpgrade() {
        var scheduler = ScanScheduler()
        _ = scheduler.request(Self.background(["archives"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)

        _ = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)
        let user = ScanRequest(scope: .locations(["simulatorDevices"]), trigger: .user)
        #expect(scheduler.request(user, at: Self.now, catalog: Self.catalog, conditions: Self.running) == .queued(user))

        #expect(scheduler.active?.trigger == .user)
        #expect(scheduler.pending == ScanRequest(scope: .locations(["derivedData", "simulatorDevices"]), trigger: .user))
    }

    @Test("Queued background work for a location just walked is held, not run back to back")
    func drainedWorkIsThrottled() {
        var scheduler = ScanScheduler()
        _ = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)
        _ = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)

        scheduler.complete(walked: ["derivedData"], at: Self.now)
        let next = scheduler.resume(at: Self.now, catalog: Self.catalog, conditions: Self.running)

        #expect(next == .declined)
        #expect(scheduler.nextWake == Self.now.addingTimeInterval(RescanThrottle.defaultInterval))
    }

    @Test("An abandoned scan starts no quiet period")
    func abandonedScanRecordsNothing() {
        var scheduler = ScanScheduler()
        _ = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)

        scheduler.complete(walked: nil, at: Self.now)
        let again = Self.background(["derivedData"])

        #expect(scheduler.request(again, at: Self.now, catalog: Self.catalog, conditions: Self.running) == .start(again))
    }

    @Test("Coverage reflects both the running and the queued scope")
    func coversRunningAndQueued() {
        var scheduler = ScanScheduler()
        _ = scheduler.request(Self.background(["archives"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)
        _ = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)

        #expect(scheduler.covers("archives", catalog: Self.catalog))
        #expect(scheduler.covers("derivedData", catalog: Self.catalog))
        #expect(!scheduler.covers("simulatorDevices", catalog: Self.catalog))
    }

    @Test("Reset forgets queued work and quiet periods but not the running scan")
    func resetKeepsActive() {
        var scheduler = ScanScheduler()
        _ = scheduler.request(Self.userEverything, at: Self.now, catalog: Self.catalog, conditions: Self.running)
        _ = scheduler.request(Self.background(["derivedData"]), at: Self.now, catalog: Self.catalog, conditions: Self.running)
        scheduler.complete(walked: ["archives"], at: Self.now)
        _ = scheduler.request(Self.userEverything, at: Self.now, catalog: Self.catalog, conditions: Self.running)

        scheduler.reset()

        #expect(scheduler.active == Self.userEverything)
        #expect(scheduler.pending == nil)
        scheduler.complete(walked: nil, at: Self.now)
        let archives = Self.background(["archives"])
        #expect(scheduler.request(archives, at: Self.now, catalog: Self.catalog, conditions: Self.running) == .start(archives))
    }
}
