import Foundation

public enum UnavailableDetector: Sendable {
    /// Reconciles device list against installed runtimes and flags devices with missing runtimes.
    public static func reconcile(devices: [SimDevice], runtimes: [SimRuntime]) -> [SimDevice] {
        let availableRuntimeIDs = Set(runtimes.flatMap { [$0.identifier, $0.runtimeIdentifier] })

        return devices.map { device in
            if device.runtime.isEmpty {
                return device
            }
            let isAvailable = availableRuntimeIDs.contains(device.runtime)
            return device.markingUnavailable(!isAvailable)
        }
    }

    public static func sort(devices: [SimDevice]) -> [SimDevice] {
        devices.sorted { lhs, rhs in
            if lhs.isUnavailable != rhs.isUnavailable {
                return lhs.isUnavailable // Unavailable first
            }
            return lhs.name.localizedStandardCompare(rhs.name) == .orderedAscending
        }
    }
}
