import Darwin
import Foundation

/// Where an area stands for the user.
public enum AccessAreaStatus: String, Sendable, Hashable, CaseIterable {
    /// macOS has never asked, so Cruftless never looks there.
    case notAsked
    case allowed
    /// The user refused the alert; macOS will not ask again.
    case notAllowed
}

/// One row of the access list: an area, its status, and what Cruftless tracks there.
public struct AccessAreaSummary: Sendable, Hashable, Identifiable {
    public let area: ProtectedArea
    public let status: AccessAreaStatus
    /// Empty for an area asked about earlier that holds nothing tracked right now.
    public let reasons: [AccessNeedReason]

    public init(area: ProtectedArea, status: AccessAreaStatus, reasons: [AccessNeedReason]) {
        self.area = area
        self.status = status
        self.reasons = reasons
    }

    public var id: ProtectedArea {
        area
    }

    /// The locations an answer about this area changes.
    public var locationIds: Set<String> {
        Set(reasons.map(\.locationId))
    }
}

/// Builds the access list from the preflight's needs and the ledger.
public enum AccessOverview {
    /// System Settings at Privacy & Security > Files and Folders.
    public static let privacySettingsURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_FilesAndFolders"
    )

    /// Lists every area with a need or already asked, in `ProtectedArea` order; only asked areas are opened, once each.
    public static func areas(
        needs: [AreaAccessNeed],
        gate: AccessGate,
        opener: AccessRequest.Opener = AccessRequest.openDirectory
    ) -> [AccessAreaSummary] {
        let reasonsByArea = Dictionary(needs.map { ($0.area, $0.reasons) }, uniquingKeysWith: { first, _ in first })
        let asked = gate.ledger.askedAreas()
        return ProtectedArea.allCases.compactMap { area in
            let reasons = reasonsByArea[area] ?? []
            guard asked.contains(area) else {
                return reasons.isEmpty ? nil : AccessAreaSummary(area: area, status: .notAsked, reasons: reasons)
            }
            guard let root = probeRoot(for: area, reasons: reasons, classifier: gate.classifier) else { return nil }
            switch opener(root) {
            case 0:
                return AccessAreaSummary(area: area, status: .allowed, reasons: reasons)
            case EPERM, EACCES:
                return AccessAreaSummary(area: area, status: .notAllowed, reasons: reasons)
            default:
                // A failure that is not a refusal says nothing about permission; the scan reports it on the row.
                return reasons.isEmpty ? nil : AccessAreaSummary(area: area, status: .allowed, reasons: reasons)
            }
        }
    }

    /// The folder whose open answers for the area: the root holding the first reason, else the home area's own folder.
    static func probeRoot(for area: ProtectedArea, reasons: [AccessNeedReason], classifier: ProtectedAreaClassifier) -> String? {
        for reason in reasons {
            if let match = classifier.areaRoot(forPath: reason.path), match.area == area { return match.root }
        }
        return classifier.defaultRoot(for: area)
    }
}
