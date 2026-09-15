import Foundation

/// Model representing a CoreSimulator device parsed from `device.plist`.
public struct SimDevice: Sendable, Hashable, Identifiable {
    public var id: String {
        udid
    }

    public let udid: String
    public let name: String
    public let runtime: String
    public let state: SimDeviceState
    public let lastUsedAt: Date?
    public let deviceDirectory: URL
    public let isUnavailable: Bool

    public var dataDirectory: URL {
        deviceDirectory.appendingPathComponent("data", isDirectory: true)
    }

    public init(
        udid: String,
        name: String,
        runtime: String,
        state: SimDeviceState,
        lastUsedAt: Date?,
        deviceDirectory: URL,
        isUnavailable: Bool = false
    ) {
        self.udid = udid
        self.name = name
        self.runtime = runtime
        self.state = state
        self.lastUsedAt = lastUsedAt
        self.deviceDirectory = deviceDirectory
        self.isUnavailable = isUnavailable
    }

    public func markingUnavailable(_ unavailable: Bool) -> SimDevice {
        SimDevice(
            udid: udid,
            name: name,
            runtime: runtime,
            state: state,
            lastUsedAt: lastUsedAt,
            deviceDirectory: deviceDirectory,
            isUnavailable: unavailable
        )
    }
}
