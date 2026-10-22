import CruftlessCore
import Foundation

public enum AndroidToolsStage: Equatable {
    case checking
    case needsSetup
    case installing
    case failed(String)
}

public extension AppModel {
    func requestAndroidAVDDeletion(_ child: ChildEntry) {
        guard !isDeleting, androidPreparationTask == nil else { return }
        guard let entry = inventory?.entries.first(where: { $0.id == LocationCatalog.androidAVDs.id }), !isRestored(entry) else {
            reportPlanFailure("Scan Android devices before choosing one to delete.")
            refreshScan()
            return
        }
        planFailure = nil
        androidToolsStage = .checking
        pushing { navigationPath.append(.androidTools(child)) }
        prepareAndroidAVD(child, install: false)
    }

    func retryAndroidAVDPreparation(_ child: ChildEntry) {
        guard androidPreparationTask == nil else { return }
        androidToolsStage = .checking
        prepareAndroidAVD(child, install: false)
    }

    func installAndroidTools(for child: ChildEntry) {
        guard androidPreparationTask == nil else { return }
        androidToolsStage = .installing
        prepareAndroidAVD(child, install: true)
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

    private func prepareAndroidAVD(_ child: ChildEntry, install: Bool) {
        let token = UUID()
        let generation = settings.platformGeneration
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
                if install {
                    _ = try await androidAVDRemoval.tools.setUp()
                } else if case .setupRequired = await androidAVDRemoval.tools.availability() {
                    guard androidPreparationID == token, !Task.isCancelled else { return }
                    androidToolsStage = .needsSetup
                    return
                }
                let request = try await androidAVDRemoval.prepare(child: child, protectedPaths: settings.protectedPathPolicy)
                guard !Task.isCancelled, androidPreparationID == token,
                      generation == settings.platformGeneration, navigationPath.last == .androidTools(child)
                else { return }
                plan { context in
                    try DeletionPlanner.androidAVD(request, context: context)
                } onSuccess: { plan in
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
}
