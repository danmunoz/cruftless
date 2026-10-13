import CruftlessCore
import Foundation
import Observation

enum CleanupSelectionStage: Equatable {
    case selection
    case gradleRisk(ChildEntry)
    case review
    case executing
    case result
}

enum CleanupSelectionAction: Hashable {
    case child(ChildEntry)
    case device(SimDevice)
    case runtime(SimRuntime)
}

struct CleanupSelectionRow: Identifiable, Hashable {
    let selectionItem: CleanupSelectionItem
    let title: String
    let subtitle: String?
    let actionLabel: String?
    let groupTitle: String?
    let action: CleanupSelectionAction

    var id: String {
        selectionItem.id
    }

    var disabledReason: String? {
        selectionItem.disabledReason
    }
}

struct CleanupSelectionGroup: Identifiable, Hashable {
    let id: String
    let title: String
    let rows: [CleanupSelectionRow]
}

@MainActor
@Observable
final class CleanupSelectionSession {
    let location: TrackedLocation
    var policyGeneration: UInt64
    var rows: [CleanupSelectionRow] = []
    var groups: [CleanupSelectionGroup] = []
    var notes: [String] = []
    var selection = CleanupSelection()
    var stage: CleanupSelectionStage = .selection
    var notice: String?
    var isReady = false
    var isRefreshing = false
    var reviewPlan: DeletionPlan?
    var reviewFreeSpaceBytes: Int64?
    var result: DeletionResult?
    var freeSpaceDelta: FreeSpaceDelta?

    @ObservationIgnored var executionTask: Task<Void, Never>?

    init(location: TrackedLocation, policyGeneration: UInt64 = 0) {
        self.location = location
        self.policyGeneration = policyGeneration
    }

    var resolution: CleanupSelectionResolution {
        selection.resolution(in: rows.map(\.selectionItem))
    }

    var canReview: Bool {
        isReady && !isRefreshing && resolution.isValid && reviewPlan == nil
    }

    var selectedRows: [CleanupSelectionRow]? {
        let ids = selection.selectedIDs
        let matches = rows.filter { ids.contains($0.id) }
        guard matches.count == ids.count,
              Set(matches.map(\.id)).count == ids.count,
              matches.allSatisfy(\.selectionItem.isSelectable)
        else { return nil }
        return matches
    }

    func update(contents: DrillDownContent, isScanned: Bool, failure: String?, protectedPaths: ProtectedPaths) {
        let previousRows = rows
        let previousNotes = notes
        rows = Self.rows(for: location, contents: contents, protectedPaths: protectedPaths)
        let grouped = Dictionary(grouping: rows) { $0.selectionItem.groupID ?? location.id }
        groups = grouped.keys.sorted { lhs, rhs in
            let leftTitle = grouped[lhs]?.first?.groupTitle ?? location.title
            let rightTitle = grouped[rhs]?.first?.groupTitle ?? location.title
            if leftTitle == "Runtime removed" { return true }
            if rightTitle == "Runtime removed" { return false }
            return leftTitle.localizedStandardCompare(rightTitle) == .orderedAscending
        }.map { id in
            CleanupSelectionGroup(
                id: id,
                title: grouped[id]?.first?.groupTitle ?? location.title,
                rows: grouped[id] ?? []
            )
        }
        notes = Self.notes(for: contents)
        isReady = isScanned && failure == nil && !contents.isUnavailable
        isRefreshing = false
        if let failure {
            notice = failure
        } else if !isReady {
            notice = "Cruftless needs a completed scan of this location before it can review a selection."
        } else if !resolution.invalidIDs.isEmpty {
            notice = "Some selected items changed or disappeared. Clear Selection to resolve them before review."
        } else {
            notice = nil
        }
        let hasPendingReview = switch stage {
        case .review, .gradleRisk: true
        default: false
        }
        if hasPendingReview, previousRows != rows || previousNotes != notes || !isReady {
            reviewPlan = nil
            stage = .selection
            if failure == nil {
                notice = "The inventory changed. Review the current selection again."
            }
        }
    }

    func invalidate(
        message: String,
        policyChanged: Bool = false,
        invalidateReview: Bool = false,
        isRefreshing: Bool = true
    ) {
        if case .executing = stage { return }
        if case .result = stage { return }
        isReady = false
        self.isRefreshing = isRefreshing
        notice = message
        if policyChanged || invalidateReview {
            switch stage {
            case .review, .gradleRisk:
                reviewPlan = nil
                stage = .selection
            case .selection, .executing, .result:
                break
            }
        }
    }

    private static func rows(
        for location: TrackedLocation,
        contents: DrillDownContent,
        protectedPaths: ProtectedPaths
    ) -> [CleanupSelectionRow] {
        if let children = contents.children { return childRows(children, location: location, protectedPaths: protectedPaths) }
        if let listing = contents.devices { return deviceRows(listing, protectedPaths: protectedPaths) }
        if let runtimes = contents.runtimes { return runtimeRows(runtimes, protectedPaths: protectedPaths) }
        return []
    }

    private static func childRows(
        _ children: [ChildEntry],
        location: TrackedLocation,
        protectedPaths: ProtectedPaths
    ) -> [CleanupSelectionRow] {
        let cacheRoots = location.id == LocationCatalog.gradleCaches.id ? location.resolveRoots() : []
        return children.map { child in
            let recognizedGradle = location.id == LocationCatalog.gradleCaches.id
                && GradleCacheEntryPolicy.isEligible(child, cacheRoots: cacheRoots)
            let eligibleGradle = recognizedGradle && !protectedPaths.intersectsCustomProtection(child.url)
            let reason = childDisabledReason(
                child,
                location: location,
                protectedPaths: protectedPaths,
                recognizedGradle: recognizedGradle,
                eligibleGradle: eligibleGradle
            )
            let selectable = reason == nil
            let path = child.url.path(percentEncoded: false)
            let subtitle = eligibleGradle ? "Recognized cache · one entry per attempt · \(path)" : path
            return CleanupSelectionRow(
                selectionItem: CleanupSelectionItem(
                    id: child.id,
                    reclaimableBytes: child.reclaimableBytes,
                    groupID: location.id,
                    isSelectable: selectable,
                    disabledReason: selectable ? nil : reason
                ),
                title: displayName(child, location: location),
                subtitle: subtitle,
                actionLabel: DesignTokens.actionLabel(for: child.tier),
                groupTitle: nil,
                action: .child(child)
            )
        }
    }

    private static func childDisabledReason(
        _ child: ChildEntry,
        location: TrackedLocation,
        protectedPaths: ProtectedPaths,
        recognizedGradle: Bool,
        eligibleGradle: Bool
    ) -> String? {
        if child.isFlagged { return "Flagged items can only be reviewed individually." }
        if recognizedGradle && !eligibleGradle { return "This entry intersects a path you marked as protected." }
        if !eligibleGradle && (protectedPaths.isProtected(child.url)
            || protectedPaths.containsProtectedDescendant(in: child.url)) {
            return "This item or a path inside it is protected."
        }
        if eligibleGradle { return nil }
        if location.mutationPolicy.isReadOnly { return "This location is read-only in Cruftless." }
        if !location.tier.isDeletable || !child.tier.isDeletable {
            return "This item can only be revealed or inspected."
        }
        return nil
    }

    private static func deviceRows(
        _ listing: (devices: [SimDevice], sizes: [String: Int64]),
        protectedPaths: ProtectedPaths
    ) -> [CleanupSelectionRow] {
        listing.devices.map { device in
            let unavailable = device.isUnavailable
            let groupID = unavailable ? "runtime-removed" : device.runtime
            let protected = protectedPaths.intersectsCustomProtection(device.deviceDirectory)
                || protectedPaths.containsCustomProtectedPath(in: device.deviceDirectory)
            let protectionReason: String? = protected ? "This simulator contains a protected path." : nil
            let reason = device.mutationIssue ?? protectionReason
            let action = deviceAction(for: device)
            let stateLabel = unavailable ? "Can't boot" : (device.state.isBooted ? "Booted" : nil)
            let captionParts: [String?] = [Naming.runtime(identifier: device.runtime), stateLabel]
            let caption = captionParts.compactMap(\.self).joined(separator: " · ")
            return CleanupSelectionRow(
                selectionItem: CleanupSelectionItem(
                    id: device.udid,
                    reclaimableBytes: listing.sizes[device.udid] ?? 0,
                    groupID: groupID,
                    isSelectable: reason == nil,
                    disabledReason: reason
                ),
                title: device.name,
                subtitle: reason ?? caption,
                actionLabel: action,
                groupTitle: unavailable ? "Runtime removed" : Naming.runtime(identifier: device.runtime),
                action: .device(device)
            )
        }
    }

    private static func runtimeRows(_ runtimes: [SimRuntime], protectedPaths: ProtectedPaths) -> [CleanupSelectionRow] {
        runtimes.map { runtime in
            let reason = runtimeDisabledReason(runtime, protectedPaths: protectedPaths)
            let state = runtime.state.isBeingDeleted ? "Removing…" : nil
            let subtitle = [runtime.build, state].compactMap(\.self).joined(separator: " · ")
            return CleanupSelectionRow(
                selectionItem: CleanupSelectionItem(
                    id: runtime.identifier,
                    reclaimableBytes: runtime.sizeBytes,
                    isSelectable: reason == nil,
                    disabledReason: reason
                ),
                title: runtime.name,
                subtitle: subtitle,
                actionLabel: "Delete",
                groupTitle: nil,
                action: .runtime(runtime)
            )
        }
    }

    private static func runtimeDisabledReason(_ runtime: SimRuntime, protectedPaths: ProtectedPaths) -> String? {
        if case let .unavailable(reason) = runtime.mutationCapability { return reason }
        let store = URL(fileURLWithPath: "/Library/Developer/CoreSimulator", isDirectory: true)
        if protectedPaths.intersectsCustomProtection(store) {
            return "A protected path intersects the simulator runtime store."
        }
        if runtime.state.isBeingDeleted { return "CoreSimulator is already removing this runtime." }
        if !runtime.isDeletable { return "This runtime is bundled with Xcode." }
        return nil
    }

    private static func deviceAction(for device: SimDevice) -> String {
        if device.isUnavailable { return device.state.isBooted ? "Shut Down and Delete" : "Delete" }
        return device.state.isBooted ? "Shut Down and Erase" : "Erase"
    }

    private static func displayName(_ child: ChildEntry, location: TrackedLocation) -> String {
        switch location.id {
        case LocationCatalog.deviceSupport.id: Naming.deviceSupportFolder(child.name)
        case LocationCatalog.derivedData.id: Naming.derivedDataFolder(child.name)
        default: child.name
        }
    }

    private static func notes(for contents: DrillDownContent) -> [String] {
        var notes: [String] = []
        if let issue = contents.inventoryIssue { notes.append(issue) }
        for diagnostic in contents.androidSDKDiagnostics {
            notes.append("\(diagnostic.category.rawValue): \(diagnostic.reason.message) · \(diagnostic.relativePath)")
        }
        if contents.androidSDKDiagnosticsTruncated {
            notes.append("Some Android SDK inventory diagnostics are omitted because the list is incomplete.")
        }
        return notes
    }
}
