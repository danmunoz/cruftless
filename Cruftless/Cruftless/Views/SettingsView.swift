import CruftlessCore
import SwiftUI

public enum SettingsSection: CaseIterable, Identifiable, Hashable {
    case general
    case support
    case about

    public var id: Self {
        self
    }

    var title: LocalizedStringResource {
        switch self {
        case .general: "General"
        case .support: "Support"
        case .about: "About"
        }
    }

    var symbol: String {
        switch self {
        case .general: "gearshape"
        case .support: "questionmark.circle"
        case .about: "info.circle"
        }
    }
}

public struct SettingsView: View {
    public let settings: SettingsModel
    public let simulatorToolchainResolver: SimulatorToolchainResolver
    public let appModel: AppModel?
    @State private var selection: SettingsSection
    private let discoversToolchainsOnAppear: Bool

    public init(
        settings: SettingsModel,
        simulatorToolchainResolver: SimulatorToolchainResolver = .shared,
        appModel: AppModel? = nil,
        initialSection: SettingsSection = .general,
        discoversToolchainsOnAppear: Bool = true
    ) {
        self.settings = settings
        self.simulatorToolchainResolver = simulatorToolchainResolver
        self.appModel = appModel
        self.discoversToolchainsOnAppear = discoversToolchainsOnAppear
        _selection = State(initialValue: initialSection)
    }

    public var body: some View {
        TabView(selection: $selection) {
            Tab(value: .general) {
                GeneralSettingsPane(settings: settings)
            } label: {
                Label(SettingsSection.general.title, systemImage: SettingsSection.general.symbol)
            }

            Tab(value: .support) {
                SupportSettingsPane(
                    resolver: simulatorToolchainResolver,
                    discoversCandidatesOnAppear: discoversToolchainsOnAppear,
                    model: appModel
                )
            } label: {
                Label(SettingsSection.support.title, systemImage: SettingsSection.support.symbol)
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
}

#if DEBUG
    #Preview("Settings: General") {
        SettingsView(settings: .preview())
    }

    #Preview("Settings: Android selected") {
        SettingsView(settings: .preview(platforms: [.android]))
    }

    #Preview("Settings: Android first") {
        SettingsView(settings: .preview(
            platforms: Set(DevelopmentPlatform.allCases),
            platformSectionOrder: .androidFirst
        ))
    }

    #Preview("Settings: Protected paths") {
        SettingsView(settings: .preview(protectedPaths: SettingsPreviewFixtures.protectedPaths))
    }

    #Preview("Settings: Support") {
        SettingsView(settings: .preview(), initialSection: .support, discoversToolchainsOnAppear: false)
    }

    #Preview("Settings: About") {
        SettingsView(settings: .preview(), initialSection: .about)
    }
#endif
