import CruftlessCore
import SwiftUI

/// The leading footer action on every Detail screen with a child listing.
struct SelectItemsButton: View {
    let location: TrackedLocation
    let model: AppModel

    var body: some View {
        Button {
            model.openSelection(for: location)
        } label: {
            Label("Select Items", systemImage: "checklist")
        }
        .disabled(model.isDeleting)
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityLabel("Select Items in \(location.title)")
        .accessibilityIdentifier("cleanup.select-items.\(location.id)")
    }
}
