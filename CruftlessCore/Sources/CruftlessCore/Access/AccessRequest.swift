import Darwin
import Foundation

/// What macOS answered when Cruftless asked about an area.
public enum AccessRequestOutcome: Sendable, Hashable {
    case allowed
    case denied
    /// The open failed for a reason other than permission, so macOS asked nothing; the ledger is left unchanged.
    case unavailable(errno: Int32)

    /// Whether macOS answered, so the area is now recorded as asked.
    public var isAnswered: Bool {
        switch self {
        case .allowed, .denied: true
        case .unavailable: false
        }
    }

    /// What to tell the user when the request changed nothing; `nil` once macOS has answered.
    public func message(for area: ProtectedArea) -> String? {
        guard case let .unavailable(code) = self else { return nil }
        let reason = String(cString: strerror(code)).lowercased()
        return "Cruftless could not open \(area.displayName) (\(reason)), so macOS did not ask. Nothing changed."
    }
}

public enum AccessRequestError: Error, Sendable, Hashable, LocalizedError {
    /// The path given does not lie in the area being asked about.
    case pathOutsideArea
    /// Another request is still waiting for macOS to answer.
    case requestInFlight

    public var errorDescription: String? {
        switch self {
        case .pathOutsideArea:
            "Cruftless has nothing in this place to ask about."
        case .requestInFlight:
            "macOS is still waiting for an answer to the previous request. Answer that alert first."
        }
    }
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

    /// Opens the root of `area` that holds `path`, and marks `area` asked only once macOS has answered.
    public func request(area: ProtectedArea, path: String) throws -> AccessRequestOutcome {
        guard let match = gate.classifier.areaRoot(forPath: path), match.area == area else {
            throw AccessRequestError.pathOutsideArea
        }
        let outcome: AccessRequestOutcome = switch opener(match.root) {
        case 0: .allowed
        case EPERM, EACCES: .denied
        case let code: .unavailable(errno: code)
        }
        if outcome.isAnswered {
            gate.ledger.markAsked(area)
        }
        return outcome
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
