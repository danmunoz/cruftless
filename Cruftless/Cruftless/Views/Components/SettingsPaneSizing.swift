import AppKit
import SwiftUI

/// Sizes a scrolling settings pane to its content height, up to a cap past which it scrolls.
private struct SettingsPaneSizing: ViewModifier {
    /// Title bar, toolbar tabs, and screen margin kept clear when the cap follows the screen.
    private static let windowChrome: CGFloat = 140

    let estimate: CGFloat
    let cap: CGFloat
    @State private var contentHeight: CGFloat?

    private var effectiveCap: CGFloat {
        guard let screenHeight = NSScreen.main?.visibleFrame.height else { return cap }
        return min(cap, max(screenHeight - Self.windowChrome, 0))
    }

    func body(content: Content) -> some View {
        content
            .onScrollGeometryChange(for: CGFloat.self) { geometry in
                geometry.contentSize.height + geometry.contentInsets.top + geometry.contentInsets.bottom
            } action: { _, height in
                contentHeight = height.rounded(.up)
            }
            .frame(width: SettingsMetrics.paneWidth, height: min(contentHeight ?? estimate, effectiveCap))
    }
}

extension View {
    /// Fits a grouped `Form` to its content height; `estimate` stands in until the first measurement.
    func settingsPaneSizing(estimate: CGFloat, cap: CGFloat) -> some View {
        modifier(SettingsPaneSizing(estimate: estimate, cap: cap))
    }
}
