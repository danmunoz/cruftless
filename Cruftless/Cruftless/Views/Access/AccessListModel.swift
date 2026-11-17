import AppKit
import CruftlessCore
import Foundation
import Observation

/// The protected areas Cruftless needs, their status, and the one request that may be waiting on macOS.
@MainActor
@Observable
public final class AccessListModel {
    public private(set) var areas: [AccessAreaSummary] = []
    /// False until the first load lands, so a host can tell "nothing needed" from "not read yet".
    public private(set) var hasLoaded = false
    public private(set) var isLoading = false
    /// The area whose macOS alert is on screen, if any.
    public private(set) var requestingArea: ProtectedArea?
    /// Per-area copy for a request that changed nothing or was refused.
    public private(set) var messages: [ProtectedArea: String] = [:]

    @ObservationIgnored private let service: AccessService
    @ObservationIgnored private let catalog: @MainActor () -> [TrackedLocation]
    @ObservationIgnored private let onAnswer: @MainActor (AccessAnswer) -> Void
    @ObservationIgnored private var loadGeneration = 0

    /// - Parameters:
    ///   - catalog: The locations whose roots the list checks, read on every load.
    ///   - onAnswer: Called once macOS has answered a request, after the list has re-read.
    public init(
        service: AccessService = .live,
        catalog: @escaping @MainActor () -> [TrackedLocation] = { LocationCatalog.all },
        onAnswer: @escaping @MainActor (AccessAnswer) -> Void = { _ in }
    ) {
        self.service = service
        self.catalog = catalog
        self.onAnswer = onAnswer
    }

    public var isRequesting: Bool {
        requestingArea != nil
    }

    /// True when some area is not allowed yet.
    public var needsAttention: Bool {
        areas.contains { $0.status != .allowed }
    }

    /// Re-reads every area; a newer call supersedes an older one still running.
    public func refresh() async {
        loadGeneration += 1
        let generation = loadGeneration
        isLoading = true
        let loaded = await service.load(catalog())
        guard generation == loadGeneration else { return }
        areas = loaded
        hasLoaded = true
        isLoading = false
    }

    /// Asks macOS about `area`; ignored while another request is waiting or once the area has been asked.
    public func allow(_ area: ProtectedArea) {
        guard requestingArea == nil,
              let summary = areas.first(where: { $0.area == area }),
              summary.status == .notAsked
        else { return }
        requestingArea = area
        messages[area] = nil
        Task { await request(summary) }
    }

    public func openPrivacySettings() {
        guard let url = AccessOverview.privacySettingsURL else { return }
        NSWorkspace.shared.open(url)
    }

    private func request(_ summary: AccessAreaSummary) async {
        do {
            let outcome = try await service.request(summary)
            messages[summary.area] = outcome.message(for: summary.area)
            await refresh()
            requestingArea = nil
            if outcome.isAnswered {
                onAnswer(AccessAnswer(area: summary.area, outcome: outcome, locationIds: summary.locationIds))
            }
        } catch {
            messages[summary.area] = error.localizedDescription
            requestingArea = nil
        }
    }
}
