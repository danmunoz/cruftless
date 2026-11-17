#if DEBUG
    import CruftlessCore
    import Foundation

    public extension PreviewFixtures {
        static let accessReasonDerivedData = AccessNeedReason(
            locationId: LocationCatalog.derivedData.id,
            title: "Derived Data location",
            path: "/Users/preview/Documents/DerivedData"
        )

        static let accessReasonXcodeBeta = AccessNeedReason(
            locationId: LocationCatalog.xcodeInstalls.id,
            title: "Xcode-beta.app",
            path: "/Users/preview/Downloads/Xcode-beta.app"
        )

        static let accessReasonArchives = AccessNeedReason(
            locationId: LocationCatalog.archives.id,
            title: "Archives location",
            path: "/Volumes/Backup/Archives"
        )

        /// The measured Xcode beside the copy `accessNeedEntries` holds back.
        static let xcodeInstallChildren: [ChildEntry] = [
            ChildEntry(
                id: "xcodeInstalls-Xcode.app",
                name: "Xcode.app",
                url: URL(fileURLWithPath: "/Applications/Xcode.app"),
                reclaimableBytes: 12_400_000_000,
                staleness: StalenessInfo(lastUsedDate: nil),
                tier: .reveal,
                consequence: LocationCatalog.xcodeInstalls.consequence
            )
        ]

        /// Areas never asked about.
        static let accessAreasNotAsked: [AccessAreaSummary] = [
            AccessAreaSummary(area: .documents, status: .notAsked, reasons: [accessReasonDerivedData]),
            AccessAreaSummary(area: .downloads, status: .notAsked, reasons: [accessReasonXcodeBeta])
        ]

        /// Areas macOS allowed, one of them holding nothing tracked right now.
        static let accessAreasAllowed: [AccessAreaSummary] = [
            AccessAreaSummary(area: .documents, status: .allowed, reasons: [accessReasonDerivedData]),
            AccessAreaSummary(area: .desktop, status: .allowed, reasons: [])
        ]

        /// Areas the user refused.
        static let accessAreasNotAllowed: [AccessAreaSummary] = [
            AccessAreaSummary(area: .downloads, status: .notAllowed, reasons: [accessReasonXcodeBeta])
        ]

        /// One area in each state.
        static let accessAreasMixed: [AccessAreaSummary] = [
            AccessAreaSummary(area: .documents, status: .allowed, reasons: [accessReasonDerivedData]),
            AccessAreaSummary(area: .downloads, status: .notAsked, reasons: [accessReasonXcodeBeta]),
            AccessAreaSummary(area: .removableVolume, status: .notAllowed, reasons: [accessReasonArchives])
        ]
    }

    public extension AccessService {
        /// Lists `areas` and answers every request with `outcome`, touching nothing on disk.
        static func preview(_ areas: [AccessAreaSummary], outcome: AccessRequestOutcome = .allowed) -> AccessService {
            AccessService(load: { _ in areas }, request: { _ in outcome })
        }

        /// Lists `areas` and never answers a request, so the list stays in flight.
        static func previewAwaitingAnswer(_ areas: [AccessAreaSummary]) -> AccessService {
            AccessService(load: { _ in areas }, request: { _ in
                try await Task.sleep(for: .seconds(3600))
                return .allowed
            })
        }
    }
#endif
