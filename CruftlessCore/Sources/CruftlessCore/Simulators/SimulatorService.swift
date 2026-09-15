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
        try await devices(reconciledAgainst: runtimes())
    }

    /// Devices reconciled against a runtime list the caller already holds.
    public func devices(reconciledAgainst runtimes: [SimRuntime]) -> [SimDevice] {
        UnavailableDetector.sort(
            devices: UnavailableDetector.reconcile(
                devices: DeviceStore.loadDevices(),
                runtimes: runtimes
            )
        )
    }

    public func runtimes() async throws -> [SimRuntime] {
        let runtimesFromPlist = ImagesPlist.load(from: imagesPlistURL)
        do {
            let runtimesFromSimctl = try await simctlRunner.listRuntimes()
            if let runtimesFromPlist, !runtimesFromPlist.isEmpty {
                return Self.merge(plistRuntimes: runtimesFromPlist, simctlRuntimes: runtimesFromSimctl)
            }
            return runtimesFromSimctl
        } catch {
            if let runtimesFromPlist, !runtimesFromPlist.isEmpty {
                return runtimesFromPlist
            }
            throw SimulatorServiceError.runtimesUnavailable(error.localizedDescription)
        }
    }

    private static func merge(plistRuntimes: [SimRuntime], simctlRuntimes: [SimRuntime]) -> [SimRuntime] {
        var bySimctlIdentifier: [String: SimRuntime] = [:]
        for runtime in simctlRuntimes {
            bySimctlIdentifier[runtime.runtimeIdentifier] = runtime
        }

        var merged = bySimctlIdentifier
        for plistRuntime in plistRuntimes {
            guard let simctlRuntime = bySimctlIdentifier[plistRuntime.runtimeIdentifier] else {
                merged[plistRuntime.runtimeIdentifier] = plistRuntime
                continue
            }
            merged[plistRuntime.runtimeIdentifier] = SimRuntime(
                identifier: simctlRuntime.identifier,
                runtimeIdentifier: plistRuntime.runtimeIdentifier,
                name: plistRuntime.name,
                build: plistRuntime.build,
                sizeBytes: simctlRuntime.sizeBytes > 0 ? simctlRuntime.sizeBytes : plistRuntime.sizeBytes,
                isDeletable: simctlRuntime.isDeletable,
                state: simctlRuntime.state
            )
        }
        return merged.values.sorted { $0.sizeBytes > $1.sizeBytes }
    }

    /// Scans a simulator device for the known bloat sub-paths (`KnownBloat`).
    public func knownBloat(for device: SimDevice) -> [BloatSubPath] {
        // A fresh set per call: hardlink dedup is per walk.
        KnownBloat.scanBloat(for: device, inodeSet: InodeSet())
    }
}
