import Foundation

/// Why an update check failed, reduced to the cases the About pane words differently.
public enum CruftlessUpdateCheckFailure: Equatable, Sendable {
    /// The running build has no release version to compare, as in a development build.
    case installedVersionUnavailable
    case checkFailed

    public init(_ error: any Error) {
        switch error as? CruftlessReleaseCheckError {
        case .missingInstalledVersion?, .invalidVersion?:
            self = .installedVersionUnavailable
        default:
            self = .checkFailed
        }
    }
}
