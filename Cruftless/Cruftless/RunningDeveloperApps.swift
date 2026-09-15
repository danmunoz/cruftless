/// Which of the two apps that write under the tracked roots is running.
public enum RunningDeveloperApps: Sendable, Hashable {
    case xcode
    case simulator
    case both

    public var warning: String {
        switch self {
        case .xcode:
            "Xcode is running. Anything it changes before deletion is skipped."
        case .simulator:
            "Simulator is running. Anything it changes before deletion is skipped."
        case .both:
            "Xcode and Simulator are running. Anything they change before deletion is skipped."
        }
    }

    public var footerLabel: String {
        switch self {
        case .xcode:
            "Xcode running"
        case .simulator:
            "Simulator running"
        case .both:
            "Xcode and Simulator running"
        }
    }
}
