import Foundation

/// One screen of the first-run welcome window, in the order shown.
public enum WelcomeStep: String, CaseIterable, Sendable, Hashable, Identifiable {
    case location
    case safety
    case setup
    case access
    case scan

    public var id: Self {
        self
    }
}

/// One line of the safety promise shown before the first scan.
public struct SafetyPromise: Sendable, Hashable, Identifiable {
    public let title: String
    public let detail: String
    /// The SF Symbol drawn beside the line.
    public let symbol: String
    /// True for the line about flagged items, which carries the warning tint.
    public let isWarning: Bool

    public init(title: String, detail: String, symbol: String, isWarning: Bool = false) {
        self.title = title
        self.detail = detail
        self.symbol = symbol
        self.isWarning = isWarning
    }

    public var id: String {
        title
    }
}

/// Decides whether the first-run welcome shows, which steps it has, and what it says.
public enum WelcomePolicy: Sendable {
    /// The defaults key recording that the welcome has been seen.
    public static let completedKey = "cruftless.welcomeCompleted"

    /// The welcome shows once, and never to someone who already has a saved scan.
    public static func shouldShow(isCompleted: Bool, hasSavedInventory: Bool) -> Bool {
        !isCompleted && !hasSavedInventory
    }

    /// The access step exists only when a tracked location lies in a protected area.
    public static func steps(hasAccessNeeds: Bool) -> [WelcomeStep] {
        WelcomeStep.allCases.filter { $0 != .access || hasAccessNeeds }
    }

    /// The step after `step`, or `nil` on the last one.
    public static func step(after step: WelcomeStep, in steps: [WelcomeStep]) -> WelcomeStep? {
        guard let index = steps.firstIndex(of: step), index + 1 < steps.count else { return nil }
        return steps[index + 1]
    }

    /// The step before `step`, or `nil` on the first one and on the scan step, which cannot be undone.
    public static func step(before step: WelcomeStep, in steps: [WelcomeStep]) -> WelcomeStep? {
        guard step != .scan, let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// True when leaving `step` forward starts the first scan.
    public static func startsScan(after step: WelcomeStep, in steps: [WelcomeStep]) -> Bool {
        self.step(after: step, in: steps) == .scan
    }

    /// The step to show when the step list changes under the current one: the nearest earlier step still listed.
    public static func resolved(_ step: WelcomeStep, in steps: [WelcomeStep]) -> WelcomeStep {
        if steps.contains(step) { return step }
        let order = WelcomeStep.allCases
        guard let index = order.firstIndex(of: step) else { return steps.first ?? .location }
        return order[..<index].last(where: steps.contains) ?? steps.first ?? .location
    }

    public static let safetySummary = "Scanning only measures. It never changes a file."

    public static let safetyPromises: [SafetyPromise] = [
        SafetyPromise(
            title: "You review every delete",
            detail: "Nothing goes until you confirm it.",
            symbol: "checklist"
        ),
        SafetyPromise(
            title: "Deletes are permanent",
            detail: "Files skip the Trash, so there is no undo.",
            symbol: "trash"
        ),
        SafetyPromise(
            title: "Flagged items go one at a time",
            detail: "Archives, and anything that cannot be rebuilt.",
            symbol: "exclamationmark.triangle.fill",
            isWarning: true
        )
    ]
}
