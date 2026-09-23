import CruftlessCore
import Foundation

/// What the app does before anyone opens the popover, and what it remembers between launches.
extension AppModel {
    /// How long after launch the unattended first scan runs.
    static var launchScanDelay: Duration {
        .seconds(5)
    }

    /// Who asked for the first scan of the session.
    enum InitialScanSource: Sendable {
        case launchTimer
        case popover
    }

    // MARK: - Entry points

    /// Called once, from the app delegate.
    func startAtLaunch() {
        restoreSavedInventory()
        startMonitoring()

        launchScanTask = Task { [weak self] in
            try? await Task.sleep(for: Self.launchScanDelay)
            guard !Task.isCancelled else { return }
            self?.startInitialScanIfNeeded(source: .launchTimer)
        }
    }

    /// Called every time the popover appears.
    func popoverDidAppear() {
        isNavigating = false
        checkRunningApps()
        startInitialScanIfNeeded(source: .popover)
    }

    // MARK: - The first scan of the session

    func startInitialScanIfNeeded(source: InitialScanSource) {
        guard !hasStartedInitialScan else { return }

        if source == .launchTimer, ProcessInfo.processInfo.isLowPowerModeEnabled {
            isAutomaticScanPaused = true
            watchForPowerStateChange()
            return
        }

        launchScanTask?.cancel()
        launchScanTask = nil
        powerStateTask?.cancel()
        powerStateTask = nil

        hasStartedInitialScan = true
        isAutomaticScanPaused = false
        startMonitoring()
        refreshScan()
    }

    /// Runs the scan that Low Power Mode held back, once it is turned off.
    private func watchForPowerStateChange() {
        guard powerStateTask == nil else { return }

        powerStateTask = Task { [weak self] in
            let changes = NotificationCenter.default.notifications(named: .NSProcessInfoPowerStateDidChange)
            for await _ in changes {
                guard !Task.isCancelled else { return }
                guard !ProcessInfo.processInfo.isLowPowerModeEnabled else { continue }
                self?.startInitialScanIfNeeded(source: .launchTimer)
                return
            }
        }
    }

    // MARK: - Filesystem monitoring

    /// Registers the FSEvents stream, once.
    func startMonitoring() {
        guard !hasStartedMonitoring else { return }
        hasStartedMonitoring = true

        Task {
            let roots = await Task.detached {
                LocationCatalog.all
                    .filter(\.tier.isDeletable)
                    .flatMap { location in
                        location.resolveRoots().map { WatchedRoot(locationId: location.id, url: $0) }
                    }
            }.value
            self.invalidator?.startMonitoring(roots: roots)
        }
    }

    // MARK: - Remembering the last scan

    /// Puts the last session's rows on screen before anything has been walked.
    private func restoreSavedInventory() {
        guard inventory == nil,
              let snapshot = inventoryStore.load(),
              let restored = snapshot.inventory(capacity: VolumeCapacity.query())
        else { return }

        inventory = restored
        // Keeps the snapshot date independent of partial-rescan timestamps.
        restoredInventoryDate = restored.scannedAt
        preferenceIssues = RootResolver.preferenceIssues()
    }

    /// Writes the current inventory out after a scan completes.
    func persistInventory() {
        guard let inventory else { return }
        inventoryStore.save(InventorySnapshot(inventory))
    }

    /// Refuses an action on a row that came from the last session, and starts the scan that will make it actionable.
    func refuseActionOnRestoredInventory() {
        let measured = restoredInventoryDate.map { "from \($0.formatted(.relative(presentation: .named)))" }
            ?? "from the last session"
        reportPlanFailure("These sizes are \(measured). Measuring now: try again in a moment.")

        startInitialScanIfNeeded(source: .popover)
        if activeScan == nil {
            // The first scan of the session has already run and the rows are still restored: it ended without an inventory.
            refreshScan()
        }
    }
}
