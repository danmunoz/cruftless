#if DEBUG
    import CruftlessCore
    import Foundation

    public enum PreviewFixtures: Sendable {
        public static let sampleCapacity = VolumeCapacity(
            totalBytes: 500_000_000_000,
            freeBytes: 2_500_000_000,
            purgeableBytes: 14_200_000_000,
            usedBytes: 336_000_000_000
        )

        public static let sampleEntries: [InventoryEntry] = [
            .sized(
                location: LocationCatalog.simulatorDevices,
                reclaimableBytes: 31_000_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -45, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/simulators"), allocatedBytes: 31_000_000_000)]
            ),
            .sized(
                location: LocationCatalog.deviceSupport,
                reclaimableBytes: 26_000_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -60, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/devicesupport"), allocatedBytes: 26_000_000_000)]
            ),
            .sized(
                location: LocationCatalog.simulatorRuntimes,
                reclaimableBytes: 23_600_000_000,
                staleness: StalenessInfo(lastUsedDate: nil),
                roots: []
            ),
            .sized(
                location: LocationCatalog.derivedData,
                reclaimableBytes: 10_000_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/deriveddata"), allocatedBytes: 23_600_000_000)]
            ),
            .sized(
                location: LocationCatalog.previewsCache,
                reclaimableBytes: 7_800_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -2, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/previews"), allocatedBytes: 7_800_000_000)]
            ),
            .sized(
                location: LocationCatalog.xcodeInstalls,
                reclaimableBytes: 7_000_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -1, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/Applications/Xcode.app"), allocatedBytes: 7_000_000_000)]
            ),
            .sized(
                location: LocationCatalog.simulatorDyldCache,
                reclaimableBytes: 6_600_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -90, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/Library/Developer/CoreSimulator/Caches/dyld"), allocatedBytes: 6_600_000_000)]
            ),
            .sized(
                location: LocationCatalog.toolchains,
                reclaimableBytes: 6_500_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -300, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/toolchains"), allocatedBytes: 6_500_000_000)]
            ),
            .sized(
                location: LocationCatalog.swiftPMCache,
                reclaimableBytes: 1_300_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -10, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/swiftpm"), allocatedBytes: 1_300_000_000)]
            ),
            .sized(
                location: LocationCatalog.ibSupport,
                reclaimableBytes: 617_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -180, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/ibsupport"), allocatedBytes: 617_000_000)]
            ),
            .sized(
                location: LocationCatalog.archives,
                reclaimableBytes: 186_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -200, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/archives"), allocatedBytes: 186_000_000)]
            ),
            .sized(
                location: LocationCatalog.codingAssistant,
                reclaimableBytes: 79_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -4, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/codingassistant"), allocatedBytes: 79_000_000)]
            ),
            .sized(
                location: LocationCatalog.productsLogsDocCache,
                reclaimableBytes: 45_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -15, to: Date())),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/products"), allocatedBytes: 45_000_000)]
            )
        ]

        /// Zero-byte and unavailable rows.
        public static let emptyStateEntries: [InventoryEntry] = [
            .sized(
                location: LocationCatalog.swiftPMCache,
                reclaimableBytes: 0,
                staleness: StalenessInfo(lastUsedDate: nil),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/swiftpm"), allocatedBytes: 0)]
            ),
            .sized(
                location: LocationCatalog.ibSupport,
                reclaimableBytes: 0,
                staleness: StalenessInfo(lastUsedDate: nil),
                roots: [RootSize(url: URL(fileURLWithPath: "/tmp/ibsupport"), allocatedBytes: 0)]
            ),
            .unavailable(location: LocationCatalog.toolchains, reason: "permission denied"),
            .unavailable(location: LocationCatalog.simulatorRuntimes, reason: "simctl did not answer")
        ]

        public static let populatedInventory = Inventory(
            entries: sampleEntries,
            capacity: sampleCapacity,
            scannedAt: Date(),
            sizesAreUpperBound: true
        )

        /// A scan part way through: the first three sample rows measured, every other catalog location still pending.
        public static let partialScanProgress: ScanProgress = {
            var progress = ScanProgress()
            progress.plan(LocationCatalog.all)
            for entry in sampleEntries.prefix(3) {
                progress.record(entry)
            }
            return progress
        }()

        /// A rescan of a list that already has every number: one location is being re-measured, the rest keep what they have.
        public static func rescanProgress(
            measuring location: TrackedLocation = LocationCatalog.derivedData
        ) -> ScanProgress {
            var progress = ScanProgress()
            progress.plan(LocationCatalog.all)
            for entry in sampleEntries where entry.location.id != location.id {
                progress.record(entry)
            }
            progress.begin(location.id)
            return progress
        }

        public static let emptyInventory = Inventory(
            entries: [],
            capacity: sampleCapacity,
            scannedAt: Date(),
            sizesAreUpperBound: true
        )

        public static let sampleChildren: [ChildEntry] = [
            ChildEntry(
                id: "child-1",
                name: "SuperApp-eszycidpyopumzgdpamntyyawoix",
                url: URL(fileURLWithPath: "/DerivedData/SuperApp-eszycidpyopumzgdpamntyyawoix"),
                reclaimableBytes: 4_500_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -45, to: Date())),
                tier: .regen,
                consequence: "Xcode recreates this on the next build."
            ),
            ChildEntry(
                id: "child-2",
                name: "ModuleCache.noindex",
                url: URL(fileURLWithPath: "/DerivedData/ModuleCache.noindex"),
                reclaimableBytes: 3_200_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -5, to: Date())),
                tier: .regen,
                consequence: "Xcode rebuilds cached Swift modules on the next build."
            ),
            ChildEntry(
                id: "child-3",
                name: "LegacyProject-zhsdkaaauramvgnxaqhyoprhlhvh",
                url: URL(fileURLWithPath: "/DerivedData/LegacyProject-zhsdkaaauramvgnxaqhyoprhlhvh"),
                reclaimableBytes: 2_300_000_000,
                staleness: StalenessInfo(lastUsedDate: Calendar.current.date(byAdding: .day, value: -120, to: Date())),
                tier: .regen,
                consequence: "Xcode recreates this on the next build."
            )
        ]
    }
#endif
