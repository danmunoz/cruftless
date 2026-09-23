import Foundation

/// Result of waiting for free space after a mutation.
public enum SpaceSettleOutcome: Sendable, Equatable {
    /// Expected space arrived and readings became stable.
    case settled
    /// The wait reached its sample cap.
    case capped

    /// User-facing note for a capped wait.
    public var note: String? {
        switch self {
        case .settled: nil
        case .capped: "Free space was still arriving when the result was measured."
        }
    }
}

/// Detects when expected free space has arrived and stabilized.
public struct SpaceSettleDetector: Sendable {
    /// Consecutive stable samples required to settle.
    public static let quietWindowSamples = 5
    /// Maximum free-space delta considered stable.
    public static let toleranceBytes: Int64 = 64_000_000
    /// Required fraction of expected bytes before settling.
    public static let arrivalNumerator: Int64 = 9
    public static let arrivalDenominator: Int64 = 10
    /// Returns the maximum sample count for an expected byte total.
    public static func capSamples(forExpectedBytes bytes: Int64) -> Int {
        max(60, Int(bytes / 105_000_000))
    }

    public enum Observation: Sendable, Equatable {
        case keepWaiting
        case settled
        case capped
    }

    public let expectedBytes: Int64
    private let baselineFreeBytes: Int64
    private let cap: Int
    private var samples = 0
    private var quietRun = 0
    private var lastFreeBytes: Int64?

    /// Creates a detector from expected bytes and pre-mutation free space.
    public init(expectedBytes: Int64, baselineFreeBytes: Int64) {
        self.expectedBytes = expectedBytes
        self.baselineFreeBytes = baselineFreeBytes
        cap = Self.capSamples(forExpectedBytes: expectedBytes)
    }

    public mutating func observe(freeBytes: Int64) -> Observation {
        samples += 1
        if let last = lastFreeBytes, abs(freeBytes - last) <= Self.toleranceBytes {
            quietRun += 1
        } else {
            quietRun = 0
        }
        lastFreeBytes = freeBytes

        let arrival = freeBytes - baselineFreeBytes
        if quietRun >= Self.quietWindowSamples,
           arrival >= (expectedBytes * Self.arrivalNumerator) / Self.arrivalDenominator {
            return .settled
        }
        if samples >= cap {
            return .capped
        }
        return .keepWaiting
    }
}
