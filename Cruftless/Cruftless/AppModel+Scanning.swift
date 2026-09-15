import CruftlessCore
import Foundation

/// Running a scan: admitting a request, following its event stream, and folding what it produced back into the model.
@MainActor
extension AppModel {

    /// Runs the scan a scope calls for: everything, or just the locations a filesystem event touched.
    func startScan(_ requested: InvalidationScope, trigger: ScanTrigger) {
        guard let scope = admit(requested, trigger: trigger) else { return }
        guard !enqueueIfBusy(scope, trigger: trigger) else { return }

        activeScan = trigger
        checkRunningApps()
        Task { await self.run(scope) }
    }

    private func admit(_ requested: InvalidationScope, trigger: ScanTrigger) -> InvalidationScope? {
        guard trigger == .background else { return requested }
        defer { scheduleThrottleWake() }
        return throttle.admit(requested, at: .now, catalog: Self.catalogIds)
    }

    private func apply(_ event: ScanEvent, to tally: inout ScanTally, tracksProgress: Bool) {
        switch event {
        case .started:
            break
        case let .planned(locations):
            if tracksProgress { scanProgress.plan(locations) }
        case let .locationStarted(locationId):
            if tracksProgress { scanProgress.begin(locationId) }
        case let .locationScanned(entry):
            tally.scannedIds.insert(entry.location.id)
            if tracksProgress { scanProgress.record(entry) }
        case let .locationContents(locationId, contents):
            drillDowns[locationId] = contents
            tally.contentsReceived.insert(locationId)
        case let .completed(newInventory):
            inventory = newInventory
            hasCompletedScanThisSession = true
            isAutomaticScanPaused = false
            persistInventory()
        case let .failed(locationId, reason):
            tally.scannedIds.insert(locationId)
            tally.failures[locationId] = reason
        }
    }

    /// Queues a request behind the scan already running, and reports whether it did.
    private func enqueueIfBusy(_ scope: InvalidationScope, trigger: ScanTrigger) -> Bool {
        guard activeScan != nil else { return false }

        pendingInvalidation = pendingInvalidation?.merged(with: scope) ?? scope
        if trigger == .user {
            pendingTrigger = .user
            activeScan = .user
        }
        return true
    }

    /// What one scan's events accumulated, folded in after the stream ends.
    private struct ScanTally {
        var failures: [String: String] = [:]
        var scannedIds: Set<String> = []
        /// Only `.locationContents` lands here.
        var contentsReceived: Set<String> = []
    }

    private func run(_ scope: InvalidationScope) async {
        var tally = ScanTally()

        let tracksProgress = activeScan == .user
        scanProgress.reset()

        for await event in await stream(for: scope) {
            apply(event, to: &tally, tracksProgress: tracksProgress)
        }

        let failures = tally.failures
        let scannedIds = tally.scannedIds
        let contentsReceived = tally.contentsReceived

        // A scan is authoritative for what it walked, listings included.
        for id in walked(from: scope, touching: scannedIds).subtracting(contentsReceived) {
            drillDowns[id] = nil
        }

        activeScan = nil
        scanProgress.reset()
        record(failures: failures, from: scope, touching: scannedIds)

        throttle.recordCompletion(of: walked(from: scope, touching: scannedIds), at: .now)

        preferenceIssues = RootResolver.preferenceIssues()

        if let queued = pendingInvalidation {
            let queuedTrigger = pendingTrigger
            pendingInvalidation = nil
            pendingTrigger = .background
            startScan(queued, trigger: queuedTrigger)
        }
    }

    /// The locations a finished scan is authoritative about: the same set `record(failures:)` replaces notices for.
    private func walked(from scope: InvalidationScope, touching scannedIds: Set<String>) -> Set<String> {
        switch scope {
        case .everything:
            Set(Self.catalogIds)
        case let .locations(requestedIds):
            requestedIds.union(scannedIds)
        }
    }

    /// Re-arms the wake-up for the throttle's earliest held location.
    private func scheduleThrottleWake() {
        throttleWake?.cancel()
        guard let wake = throttle.nextWake else {
            throttleWake = nil
            return
        }

        let delay = max(0, wake.timeIntervalSinceNow)
        throttleWake = Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard !Task.isCancelled, let self else { return }
            guard let due = throttle.release(at: .now) else {
                scheduleThrottleWake()
                return
            }
            startScan(due, trigger: .background)
        }
    }

    private func stream(for scope: InvalidationScope) async -> AsyncStream<ScanEvent> {
        switch scope {
        case .everything:
            await scanEngine.scan()
        case let .locations(ids):
            await scanEngine.rescan(locationIds: ids)
        }
    }

    /// Replaces the failure notices this scan is authoritative about, and only those.
    private func record(failures: [String: String], from scope: InvalidationScope, touching scannedIds: Set<String>) {
        switch scope {
        case .everything:
            scanFailures = failures
        case let .locations(requestedIds):
            for id in requestedIds.union(scannedIds) {
                scanFailures[id] = failures[id]
            }
        }
    }
}
