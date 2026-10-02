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
        Self.reconcile(DeviceStore.loadDevices(), against: listing)
    }

    package static func reconcile(
        _ devices: [SimDevice],
        against listing: SimulatorRuntimeListing
    ) -> [SimDevice] {
        return UnavailableDetector.sort(
            devices: UnavailableDetector.reconcile(
                devices: devices,
                runtimes: listing.runtimes
            )
        ).map { device in
            let matchingRuntime = listing.runtimes.first { $0.runtimeIdentifier == device.runtime }
            let runtimeIssue = matchingRuntime.flatMap(Self.mutationIssue(for:))
            let issue = runtimeIssue ?? (matchingRuntime == nil ? listing.mutationIssue : nil)
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
                mutationIssue: issue ?? ((listing.toolchainGeneration == nil)
                    ? "Simulator tools could not confirm the runtime catalog used by this listing. " +
                        "Refresh toolchain status before planning simulator actions."
                    : nil)
            )
        }
    }

    public func runtimes() async throws -> [SimRuntime] {
        (try await runtimeListing()).runtimes
    }

    public func runtimeListing() async throws -> SimulatorRuntimeListing {
        let runtimesFromPlist = ImagesPlist.load(from: imagesPlistURL)
        do {
            let simctlListing = try await simctlRunner.listRuntimeCatalog()
            if let runtimesFromPlist, !runtimesFromPlist.isEmpty {
                return SimulatorRuntimeListing(
                    runtimes: Self.merge(plistRuntimes: runtimesFromPlist, simctlRuntimes: simctlListing.runtimes),
                    toolchainID: simctlListing.toolchainID,
                    toolchainGeneration: simctlListing.toolchainGeneration
                )
            }
            return simctlListing
        } catch {
            if let runtimesFromPlist, !runtimesFromPlist.isEmpty {
                let reason = error.localizedDescription
                return SimulatorRuntimeListing(
                    runtimes: runtimesFromPlist.map { Self.withoutMutationCapability($0, reason: reason) },
                    mutationIssue: reason
                )
            }
            throw SimulatorServiceError.runtimesUnavailable(error.localizedDescription)
        }
    }

    private static func mutationIssue(for runtime: SimRuntime) -> String? {
        if case let .unavailable(reason) = runtime.mutationCapability { return reason }
        return nil
    }

    private static func merge(plistRuntimes: [SimRuntime], simctlRuntimes: [SimRuntime]) -> [SimRuntime] {
        var bySimctlIdentifier: [String: SimRuntime] = [:]
        for runtime in simctlRuntimes {
            bySimctlIdentifier[runtime.runtimeIdentifier] = runtime
        }

        var merged = bySimctlIdentifier
        for plistRuntime in plistRuntimes {
            guard let simctlRuntime = bySimctlIdentifier[plistRuntime.runtimeIdentifier] else {
                merged[plistRuntime.runtimeIdentifier] = withoutMutationCapability(
                    plistRuntime,
                    reason: "This runtime is visible in the local runtime catalog, but the selected Xcode could not " +
                        "confirm a simctl deletion identifier. Refresh toolchain status before planning simulator actions."
                )
                continue
            }
            merged[plistRuntime.runtimeIdentifier] = SimRuntime(
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
        return merged.values.sorted { $0.sizeBytes > $1.sizeBytes }
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
            toolchainGeneration: runtime.toolchainGeneration
        )
    }

    /// Scans a simulator device for the known bloat sub-paths (`KnownBloat`).
    public func knownBloat(for device: SimDevice) -> [BloatSubPath] {
        // A fresh set per call: hardlink dedup is per walk.
        KnownBloat.scanBloat(for: device, inodeSet: InodeSet())
    }
}
