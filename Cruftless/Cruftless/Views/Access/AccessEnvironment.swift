import SwiftUI

/// Opens the Settings window on its Access tab.
struct OpenAccessSettingsAction: Equatable {
    let handler: () -> Void

    func callAsFunction() {
        handler()
    }

    /// Every instance opens the same window, so a new closure never needs to redraw a row.
    static func == (_: Self, _: Self) -> Bool {
        true
    }
}

extension EnvironmentValues {
    /// `nil` where no window can be opened, such as a preview.
    @Entry var openAccessSettings: OpenAccessSettingsAction?
}
