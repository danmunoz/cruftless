import CruftlessCore
import SwiftUI

/// Step 3, shown only when a tracked location lies in a place macOS protects.
struct WelcomeAccessStep: View {
    let accessList: AccessListModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            WelcomeHeading(
                "Some places need your OK",
                subtitle: Text(
                    """
                    macOS protects these places. Cruftless found things it tracks in them, and it will not \
                    look inside until you allow it. macOS will confirm each one.
                    """
                )
            )
            AccessListView(model: accessList) {
                Text("Skip any of them: Cruftless shows what it could not measure, and you can allow it later in Settings.")
            }
            .scrollContentBackground(.hidden)
            .padding(.horizontal, -WelcomeAccessStep.formInset)
        }
    }

    /// The grouped form's own side margin, removed so its boxes line up with the heading.
    private static let formInset: CGFloat = 20
}
