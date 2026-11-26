import CruftlessCore
import Foundation
import SwiftUI

public enum AppRoute: Hashable {
    case detail(TrackedLocation)
    case gradleCacheRisk(location: TrackedLocation, child: ChildEntry)
    case androidTools(ChildEntry)
    case review(DeletionPlan)
    case result(DeletionResult)
    case selectionRisk(location: TrackedLocation, child: ChildEntry)
    case selectionReview(TrackedLocation)
    case selectionResult(TrackedLocation)

    var isSelectionFlow: Bool {
        switch self {
        case .selectionRisk, .selectionReview, .selectionResult: true
        default: false
        }
    }
}

public extension AppModel {
    func isSelecting(in location: TrackedLocation) -> Bool {
        selectingLocationID == location.id
    }

    /// Turns selection mode on for a Detail screen, or off when it is already on.
    func toggleSelectionMode(for location: TrackedLocation) {
        if isSelecting(in: location) {
            endSelectionMode()
        } else {
            beginSelectionMode(for: location)
        }
    }

    /// Enters selection mode with a suggestion's rows already checked; Review and confirmation still follow.
    func beginSelectionMode(for location: TrackedLocation, preselecting ids: Set<String> = []) {
        guard !isDeleting else { return }
        let session = selectionSession(for: location)
        if !ids.isEmpty, session.stage == .selection, session.isReady, !session.isRefreshing {
            session.selection.replace(with: ids, among: session.rows.map(\.selectionItem))
            if session.resolution.invalidIDs.isEmpty { session.notice = nil }
        }
        planFailure = nil
        selectingLocationID = location.id
    }

    /// Leaves selection mode and drops the selection, unless a reviewed batch is running.
    func endSelectionMode() {
        guard !isDeleting, let id = selectingLocationID else { return }
        selectingLocationID = nil
        guard let session = cleanupSessions[id], session.stage == .selection else { return }
        session.selection.clear()
        session.notice = nil
    }

    func popoverDidDisappear() {
        cancelAndroidPreparation()
        cancelPreparation()
        guard navigationPath.contains(where: \.isSelectionFlow) || selectingLocationID != nil else {
            popToRoot()
            return
        }
    }

    /// Pushes a drill-down, but never into an empty screen.
    func openDetail(for location: TrackedLocation) {
        guard preparingLocationId != location.id else { return }
        cancelPreparation()

        if !location.hasDrillDown {
            pushing { push(.detail(location)) }
            return
        }

        guard drillDowns[location.id] != nil else {
            prepare(location)
            return
        }
        pushing { push(.detail(location)) }
    }

    func openGradleCacheRiskWarning(for child: ChildEntry, in location: TrackedLocation) {
        guard location.id == LocationCatalog.gradleCaches.id,
              GradleCacheEntryPolicy.isEligible(child, cacheRoots: location.resolveRoots())
        else {
            reportPlanFailure("This Gradle cache entry is no longer eligible. Rescan and try again.")
            return
        }
        planFailure = nil
        pushing { push(.gradleCacheRisk(location: location, child: child)) }
    }

    /// Fetches a drill-down the scan has not reached yet, then pushes.
    private func prepare(_ location: TrackedLocation) {
        preparingLocationId = location.id
        prepareTask = Task { [weak self] in
            guard let self else { return }
            let contents = await coldContents(for: location)

            guard !Task.isCancelled, preparingLocationId == location.id else { return }
            preparingLocationId = nil
            prepareTask = nil

            guard let contents, !contents.isUnavailable else {
                reportPlanFailure(
                    Self.coldFailureMessage(for: location, contents: contents)
                )
                return
            }

            adopt(contents, for: location.id)
            pushing { push(.detail(location)) }
        }
    }

    private func coldContents(for location: TrackedLocation) async -> DrillDownContent? {
        switch location.id {
        case LocationCatalog.simulatorRuntimes.id:
            do {
                return try await .runtimes(simulatorService.runtimes())
            } catch {
                return .unavailable(error.localizedDescription)
            }

        case LocationCatalog.simulatorDevices.id:
            do {
                let devices = try await simulatorService.devices()
                return await .devices(devices, sizes: scanEngine.childSizes(for: location.id))
            } catch {
                return .unavailable(error.localizedDescription)
            }

        case LocationCatalog.xctestDevices.id:
            do {
                let devices = try await simulatorService.devices(in: .xctest())
                return await .devices(devices, sizes: scanEngine.childSizes(for: location.id))
            } catch {
                return .unavailable(error.localizedDescription)
            }

        case LocationCatalog.androidSDK.id, LocationCatalog.androidAVDs.id:
            return await scanEngine.androidDrillDown(for: location)

        default:
            return await .children(scanEngine.children(of: location.id))
        }
    }

    private static func coldFailureMessage(
        for location: TrackedLocation,
        contents: DrillDownContent?
    ) -> String {
        if case let .unavailable(reason) = contents { return reason }
        return "\(location.title) could not be read. Try scanning again."
    }

    /// Adopts a listing measured outside a scan.
    internal func adopt(_ contents: DrillDownContent, for locationId: String) {
        drillDowns[locationId] = contents
    }

    /// Re-reads one drill-down live, for the retry a failed screen offers.
    func reloadDrillDown(for location: TrackedLocation) {
        cancelPreparation()
        preparingLocationId = location.id
        prepareTask = Task { [weak self] in
            guard let self else { return }
            let contents = await coldContents(for: location)
            guard !Task.isCancelled, preparingLocationId == location.id else { return }
            preparingLocationId = nil
            prepareTask = nil
            guard let contents else { return }
            adopt(contents, for: location.id)
        }
    }

    /// Drops an in-flight cold fetch.
    internal func cancelPreparation() {
        prepareTask?.cancel()
        prepareTask = nil
        preparingLocationId = nil
    }

    func openReview(for plan: DeletionPlan) {
        guard !plan.isEmpty else {
            reportPlanFailure("Nothing left to delete there.")
            return
        }
        checkRunningApps()
        planFailure = nil
        // Captures Review content synchronously before navigation.
        // Hides the estimate when capacity is unavailable.
        let capacity = VolumeCapacity.query()
        reviewFreeSpaceBytes = capacity.totalBytes > 0 ? capacity.freeBytes : nil
        pushing { push(.review(plan)) }
    }

    func pop() {
        guard !isDeleting, !navigationPath.isEmpty else { return }
        planFailure = nil
        if case let .detail(location) = navigationPath.last, isSelecting(in: location) {
            endSelectionMode()
        }
        pushing { navigationPath.removeLast() }
    }

    func popToRoot() {
        guard !isDeleting else { return }
        endSelectionMode()
        pushing { navigationPath.removeAll() }
        planFailure = nil
        freeSpaceDelta = nil
        reviewFreeSpaceBytes = nil
        deletionProgress = nil
        deletionRun = nil
    }

    /// Appends a route unless it is already on top, so a double activation pushes once.
    internal func push(_ route: AppRoute) {
        guard navigationPath.last != route else { return }
        navigationPath.append(route)
    }

    /// Every mutation of `navigationPath` goes through here.
    internal func pushing(_ change: () -> Void) {
        isNavigating = true
        withAnimation(PopoverMetrics.pushAnimation, completionCriteria: .logicallyComplete) {
            change()
        } completion: { [self] in
            isNavigating = false
        }
    }
}
