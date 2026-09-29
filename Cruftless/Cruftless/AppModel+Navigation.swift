import CruftlessCore
import Foundation
import SwiftUI

public enum AppRoute: Hashable {
    case detail(TrackedLocation)
    case gradleCacheRisk(location: TrackedLocation, child: ChildEntry)
    case review(DeletionPlan)
    case result(DeletionResult)
}

public extension AppModel {
    /// Pushes a drill-down, but never into an empty screen.
    func openDetail(for location: TrackedLocation) {
        cancelPreparation()

        guard drillDowns[location.id] != nil else {
            prepare(location)
            return
        }
        pushing { navigationPath.append(.detail(location)) }
    }

    func openGradleCacheRiskWarning(for child: ChildEntry, in location: TrackedLocation) {
        guard location.id == LocationCatalog.gradleCaches.id,
              GradleCacheEntryPolicy.isEligible(child, cacheRoots: location.resolveRoots())
        else {
            reportPlanFailure("This Gradle cache entry is no longer eligible. Rescan and try again.")
            return
        }
        planFailure = nil
        pushing { navigationPath.append(.gradleCacheRisk(location: location, child: child)) }
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
            pushing { navigationPath.append(.detail(location)) }
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
        pushing { navigationPath.append(.review(plan)) }
    }

    func pop() {
        guard !navigationPath.isEmpty else { return }
        planFailure = nil
        pushing { navigationPath.removeLast() }
    }

    func popToRoot() {
        guard !isDeleting else { return }
        pushing { navigationPath.removeAll() }
        planFailure = nil
        freeSpaceDelta = nil
        reviewFreeSpaceBytes = nil
        deletionProgress = nil
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
