import Foundation

/// The toolchain fields of a diagnostic report, derived from a resolution and the usable candidates.
public struct DiagnosticToolchainSummary: Sendable, Hashable {
    public let status: DiagnosticProbeStatus
    public let source: SimulatorToolchainSource?
    public let xcodeVersions: [String]

    public init(status: DiagnosticProbeStatus, source: SimulatorToolchainSource?, xcodeVersions: [String]) {
        self.status = status
        self.source = source
        self.xcodeVersions = xcodeVersions
    }

    /// An unavailable resolution lists every usable candidate's version, since that is when they matter.
    public init(resolution: SimulatorToolchainResolution?, candidates: [SimulatorToolchain]) {
        switch resolution {
        case nil:
            self.init(status: .notChecked, source: nil, xcodeVersions: [])
        case let .some(.ready(toolchain, source, _)):
            self.init(status: .available, source: source, xcodeVersions: toolchain.version.map { [$0] } ?? [])
        case let .some(.unavailable(failure)):
            let status: DiagnosticProbeStatus = switch failure {
            case .ambiguous: .ambiguous
            case .probeFailed: .timedOut
            default: .unavailable
            }
            let versions = candidates.compactMap(\.version).prefix(DiagnosticReportBuilder.maximumXcodeVersions)
            self.init(status: status, source: nil, xcodeVersions: Array(versions))
        }
    }
}
