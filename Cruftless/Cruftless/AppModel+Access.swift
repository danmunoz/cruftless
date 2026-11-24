import CruftlessCore
import Foundation

/// Connects the access list to scanning and to the Settings window.
extension AppModel {
    /// An access list over the selected platforms that rescans whatever an answer unblocks.
    public func makeAccessListModel(service: AccessService = .live) -> AccessListModel {
        AccessListModel(
            service: service,
            catalog: { [weak self] in self?.activeCatalog.locations ?? LocationCatalog.all },
            onAnswer: { [weak self] answer in self?.accessRequestAnswered(answer) }
        )
    }

    /// Rescans the locations an answer changed, through the same path as a row's rescan.
    public func accessRequestAnswered(_ answer: AccessAnswer) {
        guard answer.outcome.isAnswered, hasStartedInitialScan else { return }
        let ids = answer.locationIds.intersection(activeCatalog.ids)
        guard !ids.isEmpty else { return }
        rescan(locationIds: ids)
    }

    /// Asks the Settings window to show its Access tab the next time it is on screen.
    public func requestAccessSettings() {
        settings.requestedSettingsSection = .access
    }
}
