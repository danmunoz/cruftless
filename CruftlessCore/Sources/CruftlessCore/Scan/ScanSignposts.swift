import Foundation
import os

/// Instrumentation for measuring scan phases via OSSignposter.
public struct ScanSignposts: Sendable {
    public static let shared = ScanSignposts()

    private let signposter: OSSignposter

    public init(subsystem: String = "com.danmunoz.Cruftless", category: String = "Scan") {
        signposter = OSSignposter(subsystem: subsystem, category: category)
    }

    public func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        let signpostID = signposter.makeSignpostID()
        return signposter.beginInterval(name, id: signpostID)
    }

    public func endInterval(_ name: StaticString, state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    public func measure<T>(_ name: StaticString, operation: () throws -> T) rethrows -> T {
        let state = beginInterval(name)
        defer { endInterval(name, state: state) }
        return try operation()
    }
}
