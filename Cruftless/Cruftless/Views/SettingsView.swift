import SwiftUI
import CruftlessCore

public enum SettingsSection: CaseIterable, Identifiable, Hashable {
    case general
    case about

    public var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .about: "info.circle"
        }
    }
}

public struct SettingsView: View {
    public let settings: SettingsModel
    @State private var selection: SettingsSection = .general

    public init(settings: SettingsModel) {
        self.settings = settings
    }

    public var body: some View {
        TabView(selection: $selection) {
            Tab(value: .general) {
                GeneralSettingsPane(settings: settings)
            } label: {
                Label(SettingsSection.general.title, systemImage: SettingsSection.general.symbol)
            }

            Tab(value: .about) {
                AboutSettingsPane()
            } label: {
                Label(SettingsSection.about.title, systemImage: SettingsSection.about.symbol)
            }
        }
        .frame(width: SettingsMetrics.paneWidth)
    }
}

enum SettingsMetrics {
    /// Matches the width Apple uses for a two-column preferences pane.
    static let paneWidth: CGFloat = 540

    /// A grouped `Form` is a scroll view with no intrinsic height, so the General pane states one.
    static func generalPaneHeight(
        protectedPathCount: Int,
        errorRowCount: Int = 0,
        includesPlatformSelection: Bool = false
    ) -> CGFloat {
        // Height with the empty-state placeholder row showing and no errors.
        let base: CGFloat = 463 + (includesPlatformSelection ? 90 : 0)
        let placeholderRow: CGFloat = 37
        let pathRow: CGFloat = 51
        let errorRow: CGFloat = 32
        let errors = CGFloat(max(0, errorRowCount)) * errorRow
        guard protectedPathCount > 0 else { return base + errors }
        let grown = base - placeholderRow + CGFloat(protectedPathCount) * pathRow
        return min(grown + errors, 700 + errors)
    }
}

#if DEBUG
    #Preview("Settings: General") {
        SettingsView(settings: .preview())
    }

    #Preview("Settings: Android selected") {
        SettingsView(settings: .preview(platforms: [.android]))
    }

    #Preview("Settings: Protected paths") {
        SettingsView(settings: .preview(protectedPaths: [
            URL(fileURLWithPath: "/Users/daniel/Developer/ImportantProject"),
            URL(fileURLWithPath: "/Users/daniel/Desktop/ReleaseArtifacts")
        ]))
    }
#endif
