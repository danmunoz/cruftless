import CruftlessCore
import Foundation

extension AppModel {
    func selectionSession(for location: TrackedLocation) -> CleanupSelectionSession {
        let session = cleanupSessions[location.id]
            ?? CleanupSelectionSession(location: location, policyGeneration: settings.platformGeneration)
        cleanupSessions[location.id] = session
        synchronizeSelectionSession(session)
        return session
    }

    func synchronizeSelectionSession(_ session: CleanupSelectionSession) {
        let location = session.location
        let policyChanged = session.policyGeneration != settings.platformGeneration
        if policyChanged {
            session.policyGeneration = settings.platformGeneration
            session.invalidate(
                message: "Protection or platform settings changed. Review the current selection again.",
                policyChanged: true,
                isRefreshing: false
            )
        }

        if case .executing = session.stage { return }
        if case .result = session.stage { return }
        guard activeCatalog.ids.contains(location.id) else {
            session.invalidate(
                message: "Enable this platform and scan again before selecting items.",
                isRefreshing: false
            )
            return
        }

        if isCleanupLocationScanPending(location.id) {
            session.invalidate(message: "Refreshing this location…")
            return
        }

        if let contents = drillDowns[location.id] {
            session.update(
                contents: contents,
                isScanned: scannedLocationIds.contains(location.id),
                failure: scanFailures[location.id],
                protectedPaths: settings.protectedPathPolicy
            )
        } else {
            session.invalidate(
                message: scanFailures[location.id]
                    ?? "Cruftless needs a completed scan of this location before it can review a selection.",
                isRefreshing: false
            )
            if scanFailures[location.id] == nil, !session.isRefreshing {
                session.isRefreshing = true
                if hasStartedInitialScan {
                    rescan(locationIds: [location.id])
                } else {
                    startInitialScanIfNeeded(source: .popover)
                }
            }
        }
    }

    private func isCleanupLocationScanPending(_ locationID: String) -> Bool {
        scope(activeScanScope, covers: locationID) || scope(pendingInvalidation, covers: locationID)
    }

    private func scope(_ scope: InvalidationScope?, covers locationID: String) -> Bool {
        guard let scope else { return false }
        return switch scope {
        case .everything:
            activeCatalog.ids.contains(locationID)
        case let .locations(ids):
            ids.contains(locationID)
        }
    }

    func refreshSelection(_ session: CleanupSelectionSession) {
        guard !isDeleting else {
            session.notice = "Wait for the current cleanup to finish before refreshing."
            return
        }
        guard activeCatalog.ids.contains(session.location.id) else {
            session.invalidate(
                message: "Enable this platform and scan again before selecting items.",
                isRefreshing: false
            )
            return
        }
        session.invalidate(message: "Refreshing this location…")
        startScan(.locations([session.location.id]), trigger: .user)
    }

    func toggleCleanupSelection(_ row: CleanupSelectionRow, in session: CleanupSelectionSession) {
        guard !isDeleting else { return }
        if session.selection.selectedIDs.contains(row.id) {
            session.selection.toggle(row.id, among: session.rows.map(\.selectionItem))
            if session.resolution.invalidIDs.isEmpty { session.notice = nil }
            return
        }
        guard session.isReady, !session.isRefreshing else { return }
        let allowsMultiple = session.location.id != LocationCatalog.gradleCaches.id
            && session.location.id != LocationCatalog.xctestDevices.id
        session.selection.toggle(row.id, among: session.rows.map(\.selectionItem), allowsMultiple: allowsMultiple)
        if session.resolution.invalidIDs.isEmpty {
            session.notice = nil
        }
    }

    func selectEligibleCleanupRows(in session: CleanupSelectionSession, groupID: String? = nil) {
        guard !isDeleting, session.isReady, !session.isRefreshing,
              session.location.id != LocationCatalog.gradleCaches.id,
              session.location.id != LocationCatalog.xctestDevices.id
        else { return }
        session.selection.selectEligible(in: session.rows.map(\.selectionItem), groupID: groupID)
    }

    func clearCleanupSelection(in session: CleanupSelectionSession) {
        guard !isDeleting else { return }
        session.selection.clear()
        if session.resolution.invalidIDs.isEmpty { session.notice = nil }
    }

    func reviewCleanupSelection(in session: CleanupSelectionSession) {
        guard !isDeleting else {
            session.notice = "Another cleanup is already running. Wait for it to finish before reviewing this selection."
            return
        }
        guard session.canReview, let rows = session.selectedRows else {
            session.notice = session.resolution.invalidIDs.isEmpty
                ? "Refresh this location before reviewing the selection."
                : "Some selected items changed or disappeared. Clear Selection to resolve them before review."
            return
        }

        if session.location.id == LocationCatalog.gradleCaches.id {
            guard rows.count == 1,
                  case let .child(child) = rows[0].action
            else {
                session.notice = "Gradle cache cleanup is limited to one recognized entry per attempt."
                return
            }
            session.stage = .gradleRisk(child)
            session.notice = nil
            pushing { navigationPath.append(.selectionRisk(location: session.location, child: child)) }
            return
        }

        planCleanupRows(rows, in: session)
    }

    func acceptCleanupGradleRisk(in session: CleanupSelectionSession, child: ChildEntry) {
        guard !isDeleting, session.isReady, !session.isRefreshing,
              !isCleanupLocationScanPending(session.location.id),
              session.selection.selectedIDs == [child.id],
              session.selectedRows?.count == 1,
              session.selectedRows?.first?.action == .child(child),
              session.policyGeneration == settings.platformGeneration
        else {
            session.stage = .selection
            session.notice = "The Gradle cache entry changed. Select it again and review this attempt."
            return
        }
        plan { context in
            try DeletionPlanner.gradleCacheChildAfterRiskAcknowledgement(
                child,
                in: session.location,
                context: context
            )
        } onSuccess: { plan in
            session.reviewPlan = plan
            session.reviewFreeSpaceBytes = VolumeCapacity.query().freeBytes
            self.checkRunningApps()
            session.stage = .review
            session.notice = nil
            pushing { navigationPath.append(.selectionReview(session.location)) }
        } onFailure: { message in
            session.stage = .selection
            session.notice = message
        }
    }

    func cancelCleanupReview(in session: CleanupSelectionSession) {
        guard !isDeleting else { return }
        session.reviewPlan = nil
        session.stage = .selection
        returnToSelection(session)
    }

    func returnToSelection(_ session: CleanupSelectionSession) {
        guard !isDeleting,
              let index = navigationPath.lastIndex(of: .selection(session.location)),
              navigationPath.count > index + 1
        else { return }
        pushing { navigationPath.removeSubrange((index + 1)...) }
    }

    func confirmCleanup(in session: CleanupSelectionSession) {
        guard !isDeleting else {
            session.notice = "Another cleanup is already running. Wait for it to finish before starting this one."
            return
        }
        guard case .review = session.stage,
              let plan = session.reviewPlan,
              session.isReady, !session.isRefreshing,
              !isCleanupLocationScanPending(session.location.id),
              plan.policyGeneration == settings.platformGeneration
        else {
            session.stage = .selection
            session.reviewPlan = nil
            session.notice = "This review is no longer current. Refresh and review the selection again."
            returnToSelection(session)
            return
        }

        isDeleting = true
        settings.isDeletionExecuting = true
        session.stage = .executing
        session.executionTask = Task { [weak self, weak session] in
            guard let self, let session else { return }
            await executeDeletion(plan: plan, cleanupSessionID: session.location.id, alreadyAdmitted: true)
            session.executionTask = nil
        }
    }

    func finishSelection(_ session: CleanupSelectionSession) {
        guard !isDeleting else { return }
        session.stage = .selection
        session.result = nil
        session.reviewPlan = nil
        session.freeSpaceDelta = nil
        session.selection.clear()
        if navigationPath.contains(.selection(session.location)) {
            returnToSelection(session)
        } else {
            popToRoot()
        }
        refreshSelection(session)
    }

    private func planCleanupRows(_ rows: [CleanupSelectionRow], in session: CleanupSelectionSession) {
        guard !rows.isEmpty else {
            session.notice = DeletionPlanningError.nothingToPlan(title: session.location.title).localizedDescription
            return
        }
        plan { context in
            switch session.location.id {
            case LocationCatalog.simulatorDevices.id, LocationCatalog.xctestDevices.id:
                let devices = try rows.map { row -> (device: SimDevice, size: Int64) in
                    guard case let .device(device) = row.action else {
                        throw DeletionPlanningError.notDeletable(title: row.title)
                    }
                    return (device, row.selectionItem.reclaimableBytes)
                }
                return try DeletionPlanner.simulatorDevices(devices, context: context)
            case LocationCatalog.simulatorRuntimes.id:
                let runtimes = try rows.map { row -> SimRuntime in
                    guard case let .runtime(runtime) = row.action else {
                        throw DeletionPlanningError.notDeletable(title: row.title)
                    }
                    return runtime
                }
                return try DeletionPlanner.simulatorRuntimes(runtimes, context: context)
            default:
                let children = try rows.map { row -> ChildEntry in
                    guard case let .child(child) = row.action else {
                        throw DeletionPlanningError.notDeletable(title: row.title)
                    }
                    return child
                }
                guard children.count == rows.count else {
                    throw DeletionPlanningError.nothingToPlan(title: session.location.title)
                }
                return try DeletionPlanner.children(children, in: session.location, context: context)
            }
        } onSuccess: { plan in
            guard plan.count == rows.count else {
                session.notice = "Cruftless could not verify every selected item. Refresh and select them again."
                return
            }
            self.checkRunningApps()
            session.reviewPlan = plan
            let capacity = VolumeCapacity.query()
            session.reviewFreeSpaceBytes = capacity.totalBytes > 0 ? capacity.freeBytes : nil
            session.stage = .review
            session.notice = nil
            pushing { navigationPath.append(.selectionReview(session.location)) }
        } onFailure: { message in
            session.notice = message
        }
    }

    func refreshCleanupSessions(affectedLocationIDs: Set<String>, failures: [String: String]) {
        for (id, session) in cleanupSessions where affectedLocationIDs.contains(id) {
            if let reason = failures[id] {
                session.invalidate(message: reason, invalidateReview: true, isRefreshing: false)
            } else if let contents = drillDowns[id] {
                let wasRefreshing = session.isRefreshing
                session.update(
                    contents: contents,
                    isScanned: scannedLocationIds.contains(id),
                    failure: nil,
                    protectedPaths: settings.protectedPathPolicy
                )
                if wasRefreshing, session.isReady, session.reviewPlan != nil {
                    session.notice = nil
                }
            } else {
                session.invalidate(
                    message: "This location's latest scan did not produce a current listing. Try Refresh.",
                    invalidateReview: true,
                    isRefreshing: false
                )
            }
        }
    }
}
