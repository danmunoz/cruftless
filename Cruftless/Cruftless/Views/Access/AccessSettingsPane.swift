import CruftlessCore
#if DEBUG
    import CruftlessFixtures
#endif
import SwiftUI

/// The Settings tab that lists protected areas and lets the user allow each one.
public struct AccessSettingsPane: View {
    let model: AccessListModel

    public init(model: AccessListModel) {
        self.model = model
    }

    public var body: some View {
        AccessListView(model: model) {
            Text(
                "Only places where Cruftless found something it tracks are listed. "
                    + "Cruftless never looks inside one until you allow it here, "
                    + "and the rest of the app works without it."
            )
        }
        .settingsPaneSizing(estimate: 260, cap: 800)
    }
}

#if DEBUG
    #Preview("Access Settings: Empty") {
        AccessSettingsPane(model: .preview([]))
    }

    #Preview("Access Settings: Not asked") {
        AccessSettingsPane(model: .preview(PreviewFixtures.accessAreasNotAsked))
    }

    #Preview("Access Settings: Allowed") {
        AccessSettingsPane(model: .preview(PreviewFixtures.accessAreasAllowed))
    }

    #Preview("Access Settings: Not allowed") {
        AccessSettingsPane(model: .preview(PreviewFixtures.accessAreasNotAllowed))
    }

    #Preview("Access Settings: Mixed") {
        AccessSettingsPane(model: .preview(PreviewFixtures.accessAreasMixed))
    }

    #Preview("Access Settings: Request in flight") {
        AccessSettingsPane(model: .previewAwaitingAnswer(PreviewFixtures.accessAreasMixed, requesting: .downloads))
    }

    #Preview("Access Settings: Request failed") {
        AccessSettingsPane(model: .preview(PreviewFixtures.accessAreasNotAsked, failing: .documents))
    }
#endif
