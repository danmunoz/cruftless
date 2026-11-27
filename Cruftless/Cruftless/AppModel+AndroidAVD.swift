import CruftlessCore
import Foundation

public enum AndroidToolsStage: Equatable {
    case checking
    case needsSetup
    /// The prepared tools are older than SDK package removal requires.
    case needsUpdate(installed: AndroidCLIVersion?)
    case installing
    case failed(String)
}

/// What the Android tools screen is preparing to remove.
public enum AndroidRemovalKind: Equatable {
    case virtualDevice
    case sdkPackage

    init(child: ChildEntry) {
        self = child.id.hasPrefix(LocationCatalog.androidSDK.id + "-") ? .sdkPackage : .virtualDevice
    }

    var location: TrackedLocation {
        self == .sdkPackage ? LocationCatalog.androidSDK : LocationCatalog.androidAVDs
    }

    var minimumToolVersion: AndroidCLIVersion? {
        self == .sdkPackage ? .minimumForSDKRemoval : nil
    }
}

public extension AppModel {
    func requestAndroidAVDDeletion(_ child: ChildEntry) {
        requestAndroidRemoval(child, scanFirst: "Scan Android devices before choosing one to delete.")
    }

    func requestAndroidSDKPackageRemoval(_ child: ChildEntry) {
        requestAndroidRemoval(child, scanFirst: "Scan the Android SDK before choosing a package to remove.")
    }

    private func requestAndroidRemoval(_ child: ChildEntry, scanFirst: String) {
        guard !isDeleting, androidPreparationTask == nil else { return }
        let location = AndroidRemovalKind(child: child).location
        guard let entry = inventory?.entries.first(where: { $0.id == location.id }), !isRestored(entry) else {
            reportPlanFailure(scanFirst)
            refreshScan()
            return
        }
        planFailure = nil
        androidToolsStage = .checking
        pushing { push(.androidTools(child)) }
        prepareAndroidRemoval(child, install: false)
    }

    func retryAndroidPreparation(_ child: ChildEntry) {
        guard androidPreparationTask == nil else { return }
        androidToolsStage = .checking
        prepareAndroidRemoval(child, install: false)
    }

    func installAndroidTools(for child: ChildEntry) {
        guard androidPreparationTask == nil else { return }
        androidToolsStage = .installing
        prepareAndroidRemoval(child, install: true)
    }

    func cancelAndroidPreparation() {
        androidPreparationTask?.cancel()
        androidPreparationTask = nil
        androidPreparationID = nil
    }

    func cancelAndroidTools() {
        cancelAndroidPreparation()
        pop()
    }

    private func prepareAndroidRemoval(_ child: ChildEntry, install: Bool) {
        let token = UUID()
        let generation = settings.platformGeneration
        let kind = AndroidRemovalKind(child: child)
        androidPreparationID = token
        androidPreparationTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if androidPreparationID == token {
                    androidPreparationTask = nil
                    androidPreparationID = nil
                }
            }
            do {
                if let stage = try await prepareTools(kind: kind, install: install) {
                    guard androidPreparationID == token, !Task.isCancelled else { return }
                    androidToolsStage = stage
                    return
                }
                let build = try await reviewBuilder(for: child, kind: kind)
                guard !Task.isCancelled, androidPreparationID == token,
                      generation == settings.platformGeneration, navigationPath.last == .androidTools(child)
                else { return }
                plan(build) { plan in
                    pushing { navigationPath.removeLast() }
                    openReview(for: plan)
                } onFailure: { reason in
                    androidToolsStage = .failed(reason)
                }
            } catch {
                guard !Task.isCancelled, androidPreparationID == token else { return }
                androidToolsStage = .failed(error.localizedDescription)
            }
        }
    }

    /// Sets the tools up when the user asked to, otherwise returns the stage to show when they are not ready.
    private func prepareTools(kind: AndroidRemovalKind, install: Bool) async throws -> AndroidToolsStage? {
        let tools = androidAVDRemoval.tools
        if install {
            _ = try await tools.setUp(minimumVersion: kind.minimumToolVersion)
            return nil
        }
        return switch await tools.availability(minimumVersion: kind.minimumToolVersion) {
        case .ready: nil
        case .setupRequired: .needsSetup
        case let .updateRequired(installed): .needsUpdate(installed: installed)
        }
    }

    /// Runs the removal service's checks, then returns the planner call that turns its request into a plan.
    private func reviewBuilder(
        for child: ChildEntry,
        kind: AndroidRemovalKind
    ) async throws -> (PlanningContext) throws -> DeletionPlan {
        switch kind {
        case .virtualDevice:
            let request = try await androidAVDRemoval.prepare(child: child, protectedPaths: settings.protectedPathPolicy)
            return { try DeletionPlanner.androidAVD(request, context: $0) }
        case .sdkPackage:
            let request = try await androidSDKPackageRemoval.prepare(child: child, protectedPaths: settings.protectedPathPolicy)
            return { try DeletionPlanner.androidSDKPackage(request, context: $0) }
        }
    }
}
