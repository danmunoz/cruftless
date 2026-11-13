import CoreGraphics

/// One scroll-geometry reading of a settings pane's form.
public struct SettingsPaneGeometry: Sendable, Equatable {
    public let contentHeight: CGFloat
    public let containerHeight: CGFloat
    public let topInset: CGFloat
    public let bottomInset: CGFloat

    public init(contentHeight: CGFloat, containerHeight: CGFloat, topInset: CGFloat = 0, bottomInset: CGFloat = 0) {
        self.contentHeight = contentHeight
        self.containerHeight = containerHeight
        self.topInset = topInset
        self.bottomInset = bottomInset
    }
}

/// A settings pane's height, derived only from the form's content so resizing the window never feeds back into it.
public struct SettingsPaneHeight: Sendable, Equatable {
    public private(set) var contentHeight: CGFloat?

    public init() {}

    /// The content height of a reading, rounded up; the container and insets track the window and are ignored.
    public static func measuredHeight(of geometry: SettingsPaneGeometry) -> CGFloat? {
        let height = geometry.contentHeight
        guard height.isFinite, height > 0 else { return nil }
        return height.rounded(.up)
    }

    public mutating func record(_ measuredHeight: CGFloat) {
        contentHeight = measuredHeight
    }

    public func height(estimate: CGFloat, cap: CGFloat) -> CGFloat {
        min(contentHeight ?? estimate, cap)
    }
}
