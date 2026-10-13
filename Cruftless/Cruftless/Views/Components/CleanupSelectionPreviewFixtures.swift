#if DEBUG
    import CruftlessCore
    import Foundation

    @MainActor
    enum CleanupSelectionPreviewFixtures {
        static let childItems = [
            ChildEntry(
                id: "preview-derived-one",
                name: "ProjectOne-SourcePackages.noindex",
                url: URL(fileURLWithPath: "/tmp/CruftlessPreview/ProjectOne-SourcePackages.noindex", isDirectory: true),
                reclaimableBytes: 2_300_000_000,
                staleness: StalenessInfo(lastUsedDate: nil),
                tier: .regen,
                consequence: LocationCatalog.derivedData.consequence
            ),
            ChildEntry(
                id: "preview-derived-two",
                name: "ProjectTwo-ModuleCache.noindex",
                url: URL(fileURLWithPath: "/tmp/CruftlessPreview/ProjectTwo-ModuleCache.noindex", isDirectory: true),
                reclaimableBytes: 1_100_000_000,
                staleness: StalenessInfo(lastUsedDate: nil),
                tier: .regen,
                consequence: LocationCatalog.derivedData.consequence
            )
        ]

        static let unavailableDevice = SimDevice(
            udid: "A93FB899-77F0-41C3-9A0C-45D22BFA0A93",
            name: "iPhone 17 Pro Max",
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
            state: .shutdown,
            lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/CruftlessPreview/unavailable"),
            isUnavailable: true,
            toolchainGeneration: UUID(uuidString: "0471A10F-7905-4131-9B7A-63091C4F2E8B")
        )

        static let bootedDevice = SimDevice(
            udid: "B93FB899-77F0-41C3-9A0C-45D22BFA0A93",
            name: "iPad Pro 11-inch (M5)",
            runtime: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
            state: .booted,
            lastUsedAt: nil,
            deviceDirectory: URL(fileURLWithPath: "/tmp/CruftlessPreview/booted"),
            toolchainGeneration: UUID(uuidString: "0471A10F-7905-4131-9B7A-63091C4F2E8B")
        )

        static func model(
            location: TrackedLocation = LocationCatalog.derivedData,
            contents: DrillDownContent = .children(childItems),
            selectedIDs: Set<String> = []
        ) -> AppModel {
            let model = AppModel()
            let session = CleanupSelectionSession(location: location, policyGeneration: model.settings.platformGeneration)
            session.update(contents: contents, isScanned: true, failure: nil, protectedPaths: .default)
            session.selection = CleanupSelection(selectedIDs: selectedIDs)
            if !session.resolution.invalidIDs.isEmpty {
                session.notice = "Some selected items changed or disappeared. Clear Selection to resolve them before review."
            }
            model.cleanupSessions[location.id] = session
            model.drillDowns[location.id] = contents
            model.scannedLocationIds = [location.id]
            model.hasStartedInitialScan = true
            return model
        }

        static func mixedSimulatorModel() -> AppModel {
            let model = model(
                location: LocationCatalog.simulatorDevices,
                contents: .devices(
                    [unavailableDevice, bootedDevice],
                    sizes: [unavailableDevice.udid: 766_000_000, bootedDevice.udid: 2_500_000_000]
                ),
                selectedIDs: [unavailableDevice.udid, bootedDevice.udid]
            )
            let session = model.cleanupSessions[LocationCatalog.simulatorDevices.id]!
            session.stage = .review
            session.reviewPlan = .batch([
                .simulatorDelete(
                    udid: unavailableDevice.udid,
                    name: unavailableDevice.name,
                    isBooted: false,
                    consequence: "Deletes this unavailable simulator completely.",
                    reclaimableBytes: 766_000_000
                ),
                .simulatorErase(
                    udid: bootedDevice.udid,
                    name: bootedDevice.name,
                    isBooted: true,
                    consequence: "Shuts this simulator down, then erases its installed apps and data.",
                    reclaimableBytes: 2_500_000_000
                )
            ], confirmLabel: "Shut Down, Delete and Erase")
            session.reviewFreeSpaceBytes = 1_600_000_000
            model.runningApps = .both
            return model
        }

        static func simulatorSelectionModel() -> AppModel {
            model(
                location: LocationCatalog.simulatorDevices,
                contents: .devices(
                    [unavailableDevice, bootedDevice],
                    sizes: [unavailableDevice.udid: 766_000_000, bootedDevice.udid: 2_500_000_000]
                )
            )
        }

        static func allDisabledModel() -> AppModel {
            model(
                location: LocationCatalog.simulatorRuntimes,
                contents: .runtimes([
                    SimRuntime(
                        identifier: "A93FB899-77F0-41C3-9A0C-45D22BFA0A93",
                        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-27-0",
                        name: "iOS 27.0 (bundled)",
                        build: "27A1",
                        sizeBytes: 12_000_000_000,
                        isDeletable: false
                    ),
                    SimRuntime(
                        identifier: "B93FB899-77F0-41C3-9A0C-45D22BFA0A93",
                        runtimeIdentifier: "com.apple.CoreSimulator.SimRuntime.iOS-26-5",
                        name: "iOS 26.5 (removing)",
                        build: "26F1",
                        sizeBytes: 8_000_000_000,
                        isDeletable: true,
                        state: .deleting
                    )
                ])
            )
        }

        static func emptyModel() -> AppModel {
            model(contents: .children([]))
        }

        static func refreshingModel() -> AppModel {
            let model = model(selectedIDs: [childItems[0].id])
            model.cleanupSessions[LocationCatalog.derivedData.id]!.invalidate(message: "Refreshing this location…")
            return model
        }

        static func failedModel() -> AppModel {
            let model = model()
            model.cleanupSessions[LocationCatalog.derivedData.id]!.invalidate(
                message: "Cruftless could not read this location. Try Refresh.", isRefreshing: false
            )
            return model
        }

        static func staleModel() -> AppModel {
            model(selectedIDs: ["missing-preview-item", childItems[0].id])
        }

        static func executingModel() -> AppModel {
            let model = mixedSimulatorModel()
            let session = model.cleanupSessions[LocationCatalog.simulatorDevices.id]!
            session.stage = .executing
            model.deletionProgress = DeletionProgress(verb: .remove, targetName: childItems[0].name, phase: .mutating)
            model.isDeleting = true
            return model
        }

        static func partialResultModel() -> AppModel {
            let model = model(location: LocationCatalog.simulatorDevices, contents: .devices(
                [unavailableDevice, bootedDevice],
                sizes: [unavailableDevice.udid: 766_000_000, bootedDevice.udid: 2_500_000_000]
            ))
            let session = model.cleanupSessions[LocationCatalog.simulatorDevices.id]!
            session.stage = .result
            session.result = DeletionResult(items: [
                ItemOutcome(
                    target: .simulatorDelete(
                        udid: unavailableDevice.udid,
                        name: unavailableDevice.name,
                        isBooted: false,
                        consequence: "",
                        reclaimableBytes: 766_000_000
                    ),
                    status: .succeeded,
                    freedBytes: 766_000_000
                ),
                ItemOutcome(
                    target: .simulatorErase(
                        udid: bootedDevice.udid,
                        name: bootedDevice.name,
                        isBooted: true,
                        consequence: "",
                        reclaimableBytes: 2_500_000_000
                    ),
                    status: .partiallyFailed(reason: "Some files remained in use"),
                    freedBytes: 1_800_000_000,
                    spaceSettle: .capped
                )
            ])
            session.freeSpaceDelta = FreeSpaceDelta(before: 1_600_000_000, after: 5_966_000_000)
            return model
        }
    }
#endif
