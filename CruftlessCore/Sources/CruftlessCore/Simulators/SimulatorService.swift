import Foundation

public enum SimulatorServiceError: Error, Sendable, Equatable, LocalizedError {
    case runtimesUnavailable(String)

    public var errorDescription: String? {
        switch self {
        case let .runtimesUnavailable(detail):
            "Cruftless couldn't list simulator runtimes, so it can't tell which simulators are still usable: \(detail)"
        }
    }
}

public struct SimulatorService: Sendable {
    private let simctlRunner: SimctlRunner
    private let imagesPlistURL: URL

    public init(simctlRunner: SimctlRunner = SimctlRunner()) {
        self.init(simctlRunner: simctlRunner, imagesPlistURL: ImagesPlist.defaultPath)
    }

    package init(simctlRunner: SimctlRunner = SimctlRunner(), imagesPlistURL: URL) {
        self.simctlRunner = simctlRunner
        self.imagesPlistURL = imagesPlistURL
    }

    /// Returns all devices, reconciled against installed runtimes with unavailable devices flagged.
    public func devices() async throws -> [SimDevice] {
        try await devices(reconciledAgainst: runtimeListing())
    }

    public func devices(in deviceSet: SimulatorDeviceSet) async throws -> [SimDevice] {
        try await devices(reconciledAgainst: runtimeListing(), in: deviceSet)
    }

    /// Devices reconciled against a runtime list the caller already holds.
    public func devices(reconciledAgainst runtimes: [SimRuntime]) -> [SimDevice] {
        let authorityRuntime = runtimes.first { $0.toolchainGeneration != nil }
        let issue = authorityRuntime == nil ? runtimes.compactMap(Self.mutationIssue(for:)).first : nil
        return devices(reconciledAgainst: SimulatorRuntimeListing(
            runtimes: runtimes,
            toolchainID: authorityRuntime?.toolchainID,
            toolchainGeneration: authorityRuntime?.toolchainGeneration,
            mutationIssue: issue
        ))
    }

    public func devices(reconciledAgainst listing: SimulatorRuntimeListing) -> [SimDevice] {
        devices(reconciledAgainst: listing, in: .ordinary())
    }

    public func devices(reconciledAgainst listing: SimulatorRuntimeListing, in deviceSet: SimulatorDeviceSet) -> [SimDevice] {
        Self.reconcile(DeviceStore.loadDevices(in: deviceSet), against: listing)
    }

    package static func reconcile(
        _ devices: [SimDevice],
        against listing: SimulatorRuntimeListing
    ) -> [SimDevice] {
        UnavailableDetector.sort(
            devices: UnavailableDetector.reconcile(
                devices: devices,
                catalog: listing.installedCatalog,
                failure: listing.catalogIssue
            )
        ).map { device in
            let matchingRuntime = listing.runtimes.first { $0.runtimeIdentifier == device.runtime }
            let availabilityIssue: String? = if case let .unknown(reason) = device.runtimeAvailability { reason } else { nil }
            let issue = listing.mutationIssue ?? (listing.catalogIssue != nil || listing.toolchainGeneration == nil
                ? (listing.catalogIssue ?? "The installed runtime catalog has no verified Xcode toolchain authority.")
                : nil)
            return SimDevice(
                udid: device.udid,
                name: device.name,
                runtime: device.runtime,
                state: device.state,
                lastUsedAt: device.lastUsedAt,
                deviceDirectory: device.deviceDirectory,
                isUnavailable: device.isUnavailable,
                toolchainID: matchingRuntime?.toolchainID ?? listing.toolchainID,
                toolchainGeneration: matchingRuntime?.toolchainGeneration ?? listing.toolchainGeneration,
                mutationIssue: issue ?? availabilityIssue ?? ((listing.toolchainGeneration == nil)
                    ? "Simulator tools could not confirm the runtime catalog used by this listing. " +
                    "Refresh toolchain status before planning simulator actions."
                    : nil),
                runtimeAvailability: device.runtimeAvailability,
                deviceSet: device.deviceSet
            )
        }
    }

    public func runtimes() async throws -> [SimRuntime] {
        try await (runtimeListing()).runtimes
    }

    public func runtimeListing() async throws -> SimulatorRuntimeListing {
        let runtimesFromPlist = ImagesPlist.load(from: imagesPlistURL)
        async let managementResult = Result { try await simctlRunner.listRuntimeCatalog() }
        async let installedResult = Result { try await simctlRunner.listInstalledRuntimeCatalog() }
        let (management, installed) = await (managementResult, installedResult)

        let fullCatalog: SimulatorRuntimeCatalog?
        let fullIssue: String?
        switch installed {
        case let .success(value): fullCatalog = value
            fullIssue = nil
        case let .failure(error): fullCatalog = nil
            fullIssue = error.localizedDescription
        }

        switch management {
        case let .success(listing):
            let assetSizes = await Self.assetSizes(for: fullCatalog)
            let merged = Self.merge(plistRuntimes: runtimesFromPlist ?? [], simctlRuntimes: listing.runtimes,
                                    installed: fullCatalog, assetSizes: assetSizes,
                                    missingManagerReason: "This installed runtime has no confirmed runtime deletion identifier.")
            let mismatch = fullCatalog?.toolchainGeneration != nil && listing.toolchainGeneration != nil &&
                fullCatalog?.toolchainGeneration != listing.toolchainGeneration
            let toolchainID = listing.toolchainID ?? fullCatalog?.toolchainID
            let generation = listing.toolchainGeneration ?? fullCatalog?.toolchainGeneration
            let runtimeAuthorityIssue = mismatch
                ? "The installed and management runtime catalogs came from different Xcode toolchains. " +
                "Refresh before planning runtime changes."
                :
                (fullCatalog?
                    .toolchainGeneration == nil ? "The installed runtime catalog could not confirm runtime deletion targets." : nil)
            let authorizedRuntimes = Self.confirmRuntimeAuthority(merged, catalog: fullCatalog, issue: runtimeAuthorityIssue)
            return SimulatorRuntimeListing(runtimes: authorizedRuntimes, toolchainID: toolchainID, toolchainGeneration: generation,
                                           mutationIssue: runtimeAuthorityIssue,
                                           installedCatalog: fullCatalog, catalogIssue: fullIssue)
        case let .failure(error):
            let reason = error.localizedDescription
            let assetSizes = await Self.assetSizes(for: fullCatalog)
            let fallback = Self.fallbackRuntimes(plistRuntimes: runtimesFromPlist ?? [], installed: fullCatalog, assetSizes: assetSizes)
            guard !fallback.isEmpty else { throw SimulatorServiceError.runtimesUnavailable(reason) }
            return SimulatorRuntimeListing(runtimes: fallback.map { Self.withoutMutationCapability($0, reason: reason) },
                                           toolchainID: fullCatalog?.toolchainID, toolchainGeneration: fullCatalog?.toolchainGeneration,
                                           mutationIssue: fullCatalog?.toolchainGeneration == nil ? reason : nil,
                                           installedCatalog: fullCatalog, catalogIssue: fullIssue)
        }
    }

    private static func confirmRuntimeAuthority(_ runtimes: [SimRuntime], catalog: SimulatorRuntimeCatalog?,
                                                issue: String?) -> [SimRuntime] {
        runtimes.map { runtime -> SimRuntime in
            let confirmed = catalog?.runtimes
                .contains { $0.identifier == runtime.runtimeIdentifier && $0.build == runtime.build } == true
            guard issue == nil, confirmed else {
                return Self.withoutMutationCapability(
                    runtime,
                    reason: issue ?? "The installed catalog did not confirm this exact runtime build."
                )
            }
            return runtime
        }
    }

    private static func fallbackRuntimes(plistRuntimes: [SimRuntime], installed: SimulatorRuntimeCatalog?,
                                         assetSizes: [String: Int64]) -> [SimRuntime] {
        var fallback = plistRuntimes.map { runtime in
            let key = "\(runtime.runtimeIdentifier)#\(runtime.build)"
            guard let measured = assetSizes[key] else { return runtime }
            return SimRuntime(identifier: runtime.identifier, runtimeIdentifier: runtime.runtimeIdentifier, name: runtime.name,
                              build: runtime.build, sizeBytes: measured, isDeletable: runtime.isDeletable,
                              state: runtime.state, mutationCapability: runtime.mutationCapability,
                              toolchainID: runtime.toolchainID, toolchainGeneration: runtime.toolchainGeneration)
        }
        if let installed {
            for runtime in installed.runtimes
                where !fallback.contains(where: { $0.runtimeIdentifier == runtime.identifier && $0.build == runtime.build }) {
                fallback.append(SimRuntime(identifier: runtime.identifier, runtimeIdentifier: runtime.identifier,
                                           name: Naming.runtime(identifier: runtime.identifier, build: runtime.build), build: runtime.build,
                                           sizeBytes: assetSizes["\(runtime.identifier)#\(runtime.build)"] ?? 0, isDeletable: false,
                                           mutationCapability: .unavailable("Manage this installed runtime in Xcode.")))
            }
        }
        return fallback
    }

    private static func mutationIssue(for runtime: SimRuntime) -> String? {
        if case let .unavailable(reason) = runtime.mutationCapability { return reason }
        return nil
    }

    private static func merge(
        plistRuntimes: [SimRuntime],
        simctlRuntimes: [SimRuntime],
        installed: SimulatorRuntimeCatalog?,
        assetSizes: [String: Int64],
        missingManagerReason: String
    ) -> [SimRuntime] {
        var bySimctlIdentifier: [String: [SimRuntime]] = [:]
        for runtime in simctlRuntimes {
            bySimctlIdentifier["\(runtime.runtimeIdentifier)#\(runtime.build)", default: []].append(runtime)
        }

        var merged: [String: SimRuntime] = [:]
        for (key, values) in bySimctlIdentifier where values.count == 1 {
            merged[key] = values[0]
        }
        for (key, values) in bySimctlIdentifier where values.count > 1 {
            let runtime = values[0]
            merged[key] = withoutMutationCapability(
                runtime,
                reason: "The runtime catalog contains ambiguous matching entries, so deletion is unavailable."
            )
        }
        for plistRuntime in plistRuntimes {
            let key = "\(plistRuntime.runtimeIdentifier)#\(plistRuntime.build)"
            guard let candidates = bySimctlIdentifier[key], candidates.count == 1, let simctlRuntime = candidates.first else {
                merged[key] = withoutMutationCapability(
                    plistRuntime,
                    reason: bySimctlIdentifier[key] == nil ? missingManagerReason : "The runtime has ambiguous deletion identifiers."
                )
                continue
            }
            merged[key] = SimRuntime(
                identifier: simctlRuntime.identifier,
                runtimeIdentifier: plistRuntime.runtimeIdentifier,
                name: plistRuntime.name,
                build: plistRuntime.build,
                sizeBytes: simctlRuntime.sizeBytes > 0 ? simctlRuntime.sizeBytes : plistRuntime.sizeBytes,
                isDeletable: simctlRuntime.isDeletable,
                state: simctlRuntime.state,
                toolchainID: simctlRuntime.toolchainID,
                toolchainGeneration: simctlRuntime.toolchainGeneration
            )
        }
        merged = addingInstalledRuntimes(to: merged, installed: installed, assetSizes: assetSizes)
        return merged.values.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    private static func addingInstalledRuntimes(
        to runtimes: [String: SimRuntime],
        installed: SimulatorRuntimeCatalog?,
        assetSizes: [String: Int64]
    ) -> [String: SimRuntime] {
        var merged = runtimes
        if let installed {
            for runtime in installed.runtimes {
                let key = "\(runtime.identifier)#\(runtime.build)"
                if let existing = merged[key] {
                    if let size = assetSizes[key] {
                        merged[key] = SimRuntime(identifier: existing.identifier, runtimeIdentifier: existing.runtimeIdentifier,
                                                 name: existing.name, build: existing.build, sizeBytes: size,
                                                 isDeletable: existing.isDeletable, state: existing.state,
                                                 mutationCapability: existing.mutationCapability,
                                                 toolchainID: existing.toolchainID, toolchainGeneration: existing.toolchainGeneration)
                    }
                } else {
                    merged[key] = SimRuntime(identifier: runtime.identifier, runtimeIdentifier: runtime.identifier,
                                             name: Naming.runtime(identifier: runtime.identifier, build: runtime.build),
                                             build: runtime.build,
                                             sizeBytes: assetSizes[key] ?? 0, isDeletable: false,
                                             mutationCapability: .unavailable("Manage this installed runtime in Xcode."))
                }
            }
        }
        return merged
    }

    private static func assetSizes(for catalog: SimulatorRuntimeCatalog?) async -> [String: Int64] {
        guard let catalog else { return [:] }
        return await SimulatorRuntimeAssetInventory.sizesBytesAsync(for: catalog.runtimes)
    }

    private static func withoutMutationCapability(_ runtime: SimRuntime, reason: String) -> SimRuntime {
        SimRuntime(
            identifier: runtime.identifier,
            runtimeIdentifier: runtime.runtimeIdentifier,
            name: runtime.name,
            build: runtime.build,
            sizeBytes: runtime.sizeBytes,
            isDeletable: runtime.isDeletable,
            state: runtime.state,
            mutationCapability: .unavailable(reason),
            toolchainID: runtime.toolchainID,
            toolchainGeneration: runtime.toolchainGeneration,
            sizeIsKnown: runtime.sizeIsKnown
        )
    }

    /// Scans a simulator device for the known bloat sub-paths (`KnownBloat`).
    public func knownBloat(for device: SimDevice) -> [BloatSubPath] {
        // A fresh set per call: hardlink dedup is per walk.
        KnownBloat.scanBloat(for: device, inodeSet: InodeSet())
    }
}
