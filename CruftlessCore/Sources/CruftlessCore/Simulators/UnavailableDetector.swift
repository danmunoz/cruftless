import Foundation

public enum UnavailableDetector: Sendable {
    /// Reconciles against a legacy image listing without claiming absence is authoritative.
    public static func reconcile(devices: [SimDevice], runtimes _: [SimRuntime]) -> [SimDevice] {
        devices.map { $0.runtime.isEmpty ? $0 : $0.markingRuntimeAvailability(.unknown("The installed runtime catalog is unavailable.")) }
    }

    public static func reconcile(devices: [SimDevice], catalog: SimulatorRuntimeCatalog?, failure: String? = nil) -> [SimDevice] {
        devices.map { device in
            guard !device.runtime.isEmpty else { return device }
            guard let catalog else {
                if let failure { return device.markingRuntimeAvailability(.unknown(failure)) }
                return device.markingRuntimeAvailability(.unknown("The installed runtime catalog is unavailable."))
            }
            let matches = catalog.runtimes.filter { $0.identifier == device.runtime }
            guard let runtime = matches.first else {
                return device.markingRuntimeAvailability(.missing)
            }
            guard matches.count == 1 else {
                return device
                    .markingRuntimeAvailability(
                        .unknown("Multiple installed runtime builds match this simulator. Refresh the runtime catalog before cleanup.")
                    )
            }
            if runtime.isAvailable { return device.markingRuntimeAvailability(.available) }
            return device
                .markingRuntimeAvailability(.installedUnavailable(runtime.availabilityError ?? "The installed runtime is unavailable."))
        }
    }

    public static func sort(devices: [SimDevice]) -> [SimDevice] {
        devices.sorted { lhs, rhs in
            let leftMissing = lhs.runtimeAvailability.isConfirmedMissing
            let rightMissing = rhs.runtimeAvailability.isConfirmedMissing
            if leftMissing != rightMissing {
                return leftMissing
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
