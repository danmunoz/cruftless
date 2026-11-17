import Darwin
import Foundation

/// What macOS answered when Cruftless asked about an area.
public enum AccessRequestOutcome: Sendable, Hashable {
    case allowed
    case denied
    /// The open failed for a reason other than permission, so macOS asked nothing; the ledger is left unchanged.
    case unavailable(errno: Int32)
}

public enum AccessRequestError: Error, Sendable, Hashable {
    /// The path given does not lie in the area being asked about.
    case pathOutsideArea
}

/// The only code allowed to open inside an area macOS has not asked about yet; one area per call.
public struct AccessRequest: Sendable {
    /// Opens `path` once and returns 0 on success or the `errno` of the failure.
    public typealias Opener = @Sendable (String) -> Int32

    private let gate: AccessGate
    private let opener: Opener

    public init(gate: AccessGate = .shared, opener: @escaping Opener = AccessRequest.openDirectory) {
        self.gate = gate
        self.opener = opener
    }

    /// Asks about the area `need` names by opening that area's root folder.
    public func request(_ need: AreaAccessNeed) throws -> AccessRequestOutcome {
        guard let path = need.reasons.first?.path else { throw AccessRequestError.pathOutsideArea }
        return try request(area: need.area, path: path)
    }

    /// Marks `area` asked, then opens the root of `area` that holds `path`.
    public func request(area: ProtectedArea, path: String) throws -> AccessRequestOutcome {
        guard let match = gate.classifier.areaRoot(forPath: path), match.area == area else {
            throw AccessRequestError.pathOutsideArea
        }
        gate.ledger.markAsked(area)
        let result = opener(match.root)
        switch result {
        case 0:
            return .allowed
        case EPERM, EACCES:
            return .denied
        default:
            gate.ledger.clearAsked(area)
            return .unavailable(errno: result)
        }
    }

    /// Opens a directory read-only and closes it straight away.
    public static func openDirectory(_ path: String) -> Int32 {
        FileAccessAudit.record(.open, path)
        let descriptor = open(path, O_RDONLY | O_DIRECTORY | O_CLOEXEC)
        guard descriptor >= 0 else { return errno }
        close(descriptor)
        return 0
    }
}
