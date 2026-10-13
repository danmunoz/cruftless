import CruftlessCore
import SwiftUI

struct SelectItemsButton: View {
    let location: TrackedLocation
    let model: AppModel

    var body: some View {
        Button {
            model.openSelection(for: location)
        } label: {
            Image(systemName: "checklist")
                .font(.system(size: 12, weight: .medium))
                .frame(width: 26, height: 26)
        }
        .disabled(model.isDeleting)
        .buttonStyle(.glass)
        .clipShape(.circle)
        .help("Select Items")
        .accessibilityLabel("Select Items in \(location.title)")
        .accessibilityIdentifier("cleanup.select-items.\(location.id)")
    }
}
