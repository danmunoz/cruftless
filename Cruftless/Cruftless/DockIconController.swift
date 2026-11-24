import AppKit
import CruftlessCore
import os

/// Shows the Dock icon while the welcome or Settings is open and hides it once neither is.
@MainActor
final class DockIconController {
    static let shared = DockIconController()

    /// How long a requested window has to appear before the icon is hidden again.
    private static let presentationGrace: Duration = .seconds(2)
    private static let logger = Logger(subsystem: "com.danmunoz.Cruftless", category: "DockIcon")

    private var observers: [NSObjectProtocol] = []
    private var isReevaluationScheduled = false
    private var presentationGraceTask: Task<Void, Never>?

    /// Starts following window changes; call once at launch.
    func start() {
        guard observers.isEmpty else { return }
        let names: [Notification.Name] = [
            NSWindow.didBecomeKeyNotification,
            NSWindow.didBecomeMainNotification,
            NSWindow.didChangeOcclusionStateNotification,
            NSWindow.didMiniaturizeNotification,
            NSWindow.didDeminiaturizeNotification,
            NSWindow.willCloseNotification
        ]
        for name in names {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated { DockIconController.shared.scheduleReevaluation() }
            })
        }
        scheduleReevaluation()
    }

    /// Shows the icon ahead of a window that is about to open, and hides it again if none appears.
    func showForPresentation() {
        setPolicy(.regular)
        presentationGraceTask?.cancel()
        presentationGraceTask = Task { [weak self] in
            try? await Task.sleep(for: Self.presentationGrace)
            guard !Task.isCancelled, let self else { return }
            presentationGraceTask = nil
            reevaluate()
        }
    }

    /// Coalesces a burst of notifications and runs after a closing window has left the screen.
    private func scheduleReevaluation() {
        guard !isReevaluationScheduled else { return }
        isReevaluationScheduled = true
        Task { [weak self] in
            await Task.yield()
            guard let self else { return }
            isReevaluationScheduled = false
            reevaluate()
        }
    }

    private func reevaluate() {
        let windows = NSApp.windows.map {
            DockIconPolicy.WindowState(
                isVisible: $0.isVisible,
                isMiniaturized: $0.isMiniaturized,
                canBecomeMain: $0.canBecomeMain
            )
        }
        if DockIconPolicy.showsDockIcon(for: windows) {
            presentationGraceTask?.cancel()
            presentationGraceTask = nil
            setPolicy(.regular)
        } else if presentationGraceTask == nil {
            setPolicy(.accessory)
        }
    }

    private func setPolicy(_ policy: NSApplication.ActivationPolicy) {
        guard NSApp.activationPolicy() != policy else { return }
        let changed = NSApp.setActivationPolicy(policy)
        Self.logger.debug("Activation policy \(policy.rawValue, privacy: .public) applied: \(changed, privacy: .public)")
    }
}
