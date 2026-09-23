import AppKit
import CruftlessCore
import Foundation
import Observation
import SwiftUI

public struct FreeSpaceDelta: Hashable, Sendable {
    public let before: Int64
    public let after: Int64
}

@MainActor
@Observable
public final class AppModel {
    public let settings: SettingsModel
    public var inventory: Inventory?

    /// How far the scan the user is watching has got.
    public internal(set) var scanProgress = ScanProgress()

    /// Who asked for the scan that is running, or nil when none is.
    enum ScanTrigger: Sendable {
        /// Launch, the Refresh button, a settings change, the rescan after a deletion: a scan someone is waiting for.
        case user
        /// An FSEvents invalidation.
        case background
    }

    var activeScan: ScanTrigger?

    /// True only while a scan someone asked for is running.
    public var isScanning: Bool {
        activeScan == .user
    }

    /// True while a filesystem event is being followed up on in the background.
    public var isRevalidating: Bool {
        activeScan == .background
    }

    var scanFailures: [String: String] = [:]

    public var scanFailure: String? {
        guard !scanFailures.isEmpty else { return nil }
        return scanFailures.keys.sorted()
            .compactMap { id in scanFailures[id].map { "\(id): \($0)" } }
            .joined(separator: "\n")
    }

    /// Seeds a notice without running a scan.
    func setScanFailure(_ reason: String, for locationId: String) {
        scanFailures[locationId] = reason
    }

    /// Which developer apps are running right now, nil when neither is.
    public var runningApps: RunningDeveloperApps?

    /// The full sentence, shown in Review and carried by the footer's `.help` and accessibility label.
    public var runningAppsWarning: String? {
        runningApps?.warning
    }

    /// The footer's condensed form of the same fact: "Xcode running".
    public var runningAppsFooterLabel: String? {
        runningApps?.footerLabel
    }

    /// What each drill-down screen renders, produced by the scan that measured the location, keyed by location id.
    public internal(set) var drillDowns: [String: DrillDownContent] = [:]

    public internal(set) var preparingLocationId: String?

    /// The in-flight cold fetch, so a second click supersedes the first and closing the popover cancels it.
    var prepareTask: Task<Void, Never>?

    /// True from the moment a push or pop is requested until its animation has logically completed.
    public internal(set) var isNavigating = false

    public var navigationPath: [AppRoute] = []
    public var freeSpaceDelta: FreeSpaceDelta?

    /// Free space captured when Review opens.
    var reviewFreeSpaceBytes: Int64?

    /// Custom Xcode locations (Derived Data, Archives) refused for safety, with the default root used in their place.
    public var preferenceIssues: [RootPreferenceIssue] = []

    public var planFailure: String?

    /// True while a plan is being executed.
    public private(set) var isDeleting = false

    /// Current deletion progress shown in Review.
    public internal(set) var deletionProgress: DeletionProgress?

    public let scanEngine: ScanEngine
    public let simulatorService: SimulatorService
    public let deletionExecutor: DeletionExecutor
    var invalidator: FSEventsInvalidator?

    var pendingInvalidation: InvalidationScope?
    var pendingTrigger: ScanTrigger = .background

    var hasStartedMonitoring = false
    var hasStartedInitialScan = false
    /// Location IDs measured during this session.
    var scannedLocationIds: Set<String> = []

    /// The delayed first scan, cancelled if the popover asks for one sooner.
    var launchScanTask: Task<Void, Never>?

    /// Watches for Low Power Mode ending, and only exists while it is on.
    var powerStateTask: Task<Void, Never>?

    var isAutomaticScanPaused = false

    let inventoryStore: InventoryStore

    /// Whether the location still uses restored snapshot data.
    public func isRestored(_ entry: InventoryEntry) -> Bool {
        inventory != nil && !scannedLocationIds.contains(entry.location.id)
    }

    /// Timestamp of the restored snapshot rows.
    var restoredInventoryDate: Date?

    /// Bounds how often a filesystem event may rescan the same location.
    var throttle = RescanThrottle()

    /// Wakes when the throttle's earliest held location comes due.
    var throttleWake: Task<Void, Never>?

    static let catalogIds = LocationCatalog.all.map(\.id)

    /// True once there are rows to show: from a scan this session, or restored from the last one.
    public var hasScanned: Bool {
        inventory != nil
    }

    public init(
        scanEngine: ScanEngine = ScanEngine(),
        simulatorService: SimulatorService = SimulatorService(),
        deletionExecutor: DeletionExecutor = DeletionExecutor(),
        settings: SettingsModel = SettingsModel(),
        inventoryStore: InventoryStore = InventoryStore()
    ) {
        self.scanEngine = scanEngine
        self.simulatorService = simulatorService
        self.deletionExecutor = deletionExecutor
        self.settings = settings
        self.inventoryStore = inventoryStore

        invalidator = FSEventsInvalidator { [weak self] scope in
            Task { @MainActor in
                self?.startScan(scope, trigger: .background)
            }
        }

        // Protected paths feed root resolution, not just planning, so the list is stale the moment one is added or removed.
        settings.onProtectedPathsChanged = { [weak self] in
            self?.refreshScan()
        }
    }

    public func checkRunningApps() {
        let running = NSWorkspace.shared.runningApplications
        let xcodeRunning = running.contains { $0.bundleIdentifier == "com.apple.dt.Xcode" }
        let simRunning = running.contains { $0.bundleIdentifier == "com.apple.iphonesimulator" }

        if xcodeRunning, simRunning {
            runningApps = .both
        } else if xcodeRunning {
            runningApps = .xcode
        } else if simRunning {
            runningApps = .simulator
        } else {
            runningApps = nil
        }
    }

    /// Rescans everything.
    public func refreshScan() {
        startScan(.everything, trigger: .user)
    }

    /// Rescans only the given locations, merging into the current inventory.
    public func rescan(locationIds: Set<String>) {
        startScan(.locations(locationIds), trigger: .user)
    }

    public func reportPlanFailure(_ message: String) {
        planFailure = message
    }

    public func plan(_ build: (PlanningContext) throws -> DeletionPlan) {
        do {
            let plan = try build(PlanningContext.live(protectedPaths: settings.protectedPathPolicy))
            openReview(for: plan)
        } catch {
            reportPlanFailure(error.localizedDescription)
        }
    }

    public func executeDeletion(plan: DeletionPlan) async {
        guard !isDeleting else { return }
        isDeleting = true
        defer { isDeleting = false }

        let before = VolumeCapacity.query().freeBytes
        let result = await deletionExecutor.execute(plan) { [weak self] progress in
            Task { @MainActor in self?.deletionProgress = progress }
        }
        deletionProgress = nil
        freeSpaceDelta = FreeSpaceDelta(before: before, after: VolumeCapacity.query().freeBytes)
        // Rescans only locations affected by the plan.
        startScan(plan.rescanScope, trigger: .user)

        // Result replaces Review in place, so Back from Result never lands on a plan that has already been executed.
        pushing {
            if case .review = navigationPath.last {
                navigationPath.removeLast()
            }
            navigationPath.append(.result(result))
        }
    }
}
