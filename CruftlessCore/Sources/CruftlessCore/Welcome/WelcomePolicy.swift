import Foundation

/// One screen of the first-run welcome window.
public enum WelcomeStep: String, CaseIterable, Sendable, Hashable, Identifiable {
    case location
    case safety
    case access
    case setup

    public var id: Self {
        self
    }
}

/// One line of the safety promise shown before the first scan.
public struct SafetyPromise: Sendable, Hashable, Identifiable {
    public let title: String
    public let detail: String

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

    /// The step before `step`, or `nil` on the first one.
    public static func step(before step: WelcomeStep, in steps: [WelcomeStep]) -> WelcomeStep? {
        guard let index = steps.firstIndex(of: step), index > 0 else { return nil }
        return steps[index - 1]
    }

    /// The step to show when the step list changes under the current one.
    public static func resolved(_ step: WelcomeStep, in steps: [WelcomeStep]) -> WelcomeStep {
        if steps.contains(step) { return step }
        return steps.last ?? .location
    }

    public static let safetyPromises: [SafetyPromise] = [
        SafetyPromise(
            title: "Scanning only measures",
            detail: "Every delete goes through a Review step where you see exactly what will go."
        ),
        SafetyPromise(
            title: "Deletes are permanent",
            detail: "They skip the Trash on purpose, so the space comes back right away."
        ),
        SafetyPromise(
            title: "Risky items are flagged",
            detail: "Archives and anything that cannot be rebuilt are never part of a batch."
        )
    ]
}
