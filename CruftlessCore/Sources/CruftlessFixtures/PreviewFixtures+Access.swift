#if DEBUG
    import CruftlessCore
    import Foundation

    public extension PreviewFixtures {
        /// Rows held back by the access gate: never asked, refused by macOS, and partly measured.
        static let accessNeedEntries: [InventoryEntry] = [
            .needsAccess(
                location: LocationCatalog.derivedData,
                need: LocationAccessNeed(
                    blocked: [BlockedAccess(
                        path: "/Users/preview/Documents/DerivedData",
                        area: .documents,
                        state: .notAsked,
                        reason: "Derived Data location"
                    )],
                    measuredRootCount: 0
                )
            ),
            .needsAccess(
                location: LocationCatalog.archives,
                need: LocationAccessNeed(
                    blocked: [BlockedAccess(
                        path: "/Volumes/Backup/Archives",
                        area: .removableVolume,
                        state: .notAllowed,
                        reason: "Archives location"
                    )],
                    measuredRootCount: 0
                )
            ),
            .sized(
                location: LocationCatalog.xcodeInstalls,
                reclaimableBytes: 12_400_000_000,
                staleness: StalenessInfo(lastUsedDate: nil),
                roots: [RootSize(url: URL(fileURLWithPath: "/Applications/Xcode.app"), allocatedBytes: 12_400_000_000)],
                accessNeed: LocationAccessNeed(
                    blocked: [BlockedAccess(
                        path: "/Users/preview/Downloads/Xcode-beta.app",
                        area: .downloads,
                        state: .notAsked,
                        reason: "Xcode-beta.app"
                    )],
                    measuredRootCount: 1
                )
            )
        ]
    }
#endif
