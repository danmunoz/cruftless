import CruftlessCore
import Foundation

/// Running a scan: admitting a request, following its event stream, and folding what it produced back into the model.
@MainActor
extension AppModel {
    func platformSelectionDidChange(_ catalog: ActiveCatalog) {
        guard !isDeleting else { return }
        cancelPreparation()
        planFailure = nil
        scannedLocationIds = []
        throttleWake?.cancel()
        throttleWake = nil
        throttle = RescanThrottle()
        pendingInvalidation = nil
        pendingTrigger = .background
        scanProgress.reset()
        scanFailures = scanFailures.filter { catalog.ids.contains($0.key) }
        if !catalog.selection.platforms.contains(.apple) {
            preferenceIssues = []
        }
        drillDowns = drillDowns.filter { catalog.ids.contains($0.key) }

        if let inventory {
            let retainsGradleCleanableBytes = catalog.ids.contains(LocationCatalog.gradleCaches.id)
                && inventory.entries.contains { $0.location.id == LocationCatalog.gradleCaches.id }
            self.inventory = Inventory(
                entries: inventory.entries.filter { catalog.ids.contains($0.id) },
                capacity: inventory.capacity,
                scannedAt: inventory.scannedAt,
                sizesAreUpperBound: inventory.sizesAreUpperBound,
                optInReclaimableBytes: retainsGradleCleanableBytes
                    ? inventory.optInReclaimableBytes
                    : 0
            )
        }

        pushing { navigationPath.removeAll(where: shouldRemoveRouteAfterPlatformChange) }

        Task {
            await scanEngine.invalidate(generation: catalog.generation)
        }
        startMonitoring(for: catalog)
        refreshScan()
    }

    /// Runs the scan a scope calls for: everything, or just the locations a filesystem event touched.
    func startScan(_ requested: InvalidationScope, trigger: ScanTrigger) {
        let catalog = activeCatalog
        guard let scope = admit(requested, trigger: trigger, catalog: catalog) else { return }
        guard !enqueueIfBusy(scope, trigger: trigger) else { return }

        activeScan = trigger
        checkRunningApps()
        Task { await self.run(scope, catalog: catalog) }
    }

    private func admit(
        _ requested: InvalidationScope,
        trigger: ScanTrigger,
        catalog: ActiveCatalog
    ) -> InvalidationScope? {
        guard trigger == .background else { return requested }
        defer { scheduleThrottleWake() }
        return throttle.admit(requested, at: .now, catalog: Array(catalog.ids))
    }

    private func shouldRemoveRouteAfterPlatformChange(_ route: AppRoute) -> Bool {
        if case .result = route { return false }
        return true
    }

    private func apply(
        _ event: ScanEvent,
        to tally: inout ScanTally,
        tracksProgress: Bool,
        generation: UInt64
    ) {
        guard settings.platformGeneration == generation else { return }
        if tracksProgress { updateProgress(for: event) }
        switch event {
        case .started:
            break
        case .planned, .locationStarted:
            break
        case let .locationScanned(entry):
            tally.scannedIds.insert(entry.location.id)
            tally.landedIds.insert(entry.location.id)
        case let .locationContents(locationId, contents):
            drillDowns[locationId] = contents
            tally.contentsReceived.insert(locationId)
            if tracksProgress, locationId == LocationCatalog.gradleCaches.id {
                scanProgress.recordOptInReclaimableBytes(
                    GradleCacheEntryPolicy.cleanableBytes(
                        in: contents.children ?? [],
                        cacheRoots: LocationCatalog.gradleCaches.resolveRoots()
                    )
                )
            }
        case let .completed(newInventory):
            inventory = newInventory
            scannedLocationIds.formUnion(tally.landedIds)
            isAutomaticScanPaused = false
            persistInventory()
        case let .failed(locationId, reason):
            tally.scannedIds.insert(locationId)
            tally.failures[locationId] = reason
        }
    }

    private func updateProgress(for event: ScanEvent) {
        switch event {
        case .started, .completed, .locationContents, .failed:
            break
        case let .planned(locations):
            scanProgress.plan(locations)
        case let .locationStarted(locationId):
            scanProgress.begin(locationId)
        case let .locationScanned(entry):
            scanProgress.record(entry)
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
        /// Records locations that produce `.locationScanned`.
        var landedIds: Set<String> = []
        /// Only `.locationContents` lands here.
        var contentsReceived: Set<String> = []
    }

    private func run(_ scope: InvalidationScope, catalog: ActiveCatalog) async {
        var tally = ScanTally()

        let tracksProgress = activeScan == .user
        scanProgress.reset()

        for await event in await stream(for: scope, catalog: catalog) {
            apply(event, to: &tally, tracksProgress: tracksProgress, generation: catalog.generation)
        }

        guard settings.platformGeneration == catalog.generation else {
            activeScan = nil
            scanProgress.reset()
            if let queued = pendingInvalidation {
                let queuedTrigger = pendingTrigger
                pendingInvalidation = nil
                pendingTrigger = .background
                startScan(queued, trigger: queuedTrigger)
            }
            return
        }

        let failures = tally.failures
        let scannedIds = tally.scannedIds
        let contentsReceived = tally.contentsReceived

        // A scan is authoritative for what it walked, listings included.
        for id in walked(from: scope, touching: scannedIds, catalog: catalog).subtracting(contentsReceived) {
            drillDowns[id] = nil
        }

        activeScan = nil
        scanProgress.reset()
        record(failures: failures, from: scope, touching: scannedIds)

        throttle.recordCompletion(of: walked(from: scope, touching: scannedIds, catalog: catalog), at: .now)

        preferenceIssues = catalog.selection.platforms.contains(.apple) ? RootResolver.preferenceIssues() : []

        if let queued = pendingInvalidation {
            let queuedTrigger = pendingTrigger
            pendingInvalidation = nil
            pendingTrigger = .background
            startScan(queued, trigger: queuedTrigger)
        }
    }

    /// The locations a finished scan is authoritative about: the same set `record(failures:)` replaces notices for.
    private func walked(
        from scope: InvalidationScope,
        touching scannedIds: Set<String>,
        catalog: ActiveCatalog
    ) -> Set<String> {
        switch scope {
        case .everything:
            catalog.ids
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

    private func stream(for scope: InvalidationScope, catalog: ActiveCatalog) async -> AsyncStream<ScanEvent> {
        switch scope {
        case .everything:
            await scanEngine.scan(catalog: catalog.locations, generation: catalog.generation)
        case let .locations(ids):
            await scanEngine.rescan(
                locationIds: ids.intersection(catalog.ids),
                catalog: catalog.locations,
                generation: catalog.generation
            )
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
