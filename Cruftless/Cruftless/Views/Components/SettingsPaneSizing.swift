import AppKit
import CruftlessCore
import SwiftUI

/// Sizes a scrolling settings pane to its content height, up to a cap past which it scrolls.
private struct SettingsPaneSizing: ViewModifier {
    /// Title bar, toolbar tabs, and screen margin kept clear when the cap follows the screen.
    private static let windowChrome: CGFloat = 140

    let estimate: CGFloat
    let cap: CGFloat
    @State private var sizing = SettingsPaneHeight()

    private var effectiveCap: CGFloat {
        guard let screenHeight = NSScreen.main?.visibleFrame.height else { return cap }
        return min(cap, max(screenHeight - Self.windowChrome, 0))
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat?.self) { geometry in
                SettingsPaneHeight.measuredHeight(of: SettingsPaneGeometry(
                    contentHeight: geometry.contentSize.height,
                    containerHeight: geometry.containerSize.height,
                    topInset: geometry.contentInsets.top,
                    bottomInset: geometry.contentInsets.bottom
                ))
            } action: { _, height in
                guard let height, height != sizing.contentHeight else { return }
                sizing.record(height)
            }
            .frame(width: SettingsMetrics.paneWidth, height: sizing.height(estimate: estimate, cap: effectiveCap))
    }
}

extension View {
    /// Fits a grouped `Form` to its content height; `estimate` stands in until the first measurement.
    func settingsPaneSizing(estimate: CGFloat, cap: CGFloat) -> some View {
        modifier(SettingsPaneSizing(estimate: estimate, cap: cap))
    }
}
