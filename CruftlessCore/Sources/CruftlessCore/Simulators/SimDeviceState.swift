import Foundation

/// CoreSimulator device execution state.
public enum SimDeviceState: Int, Sendable, Hashable, Codable {
    case other = 0
    case shutdown = 1
    case booted = 3

    public var isBooted: Bool {
        self == .booted
    }

    public var isShutdown: Bool {
        self == .shutdown
    }
}
