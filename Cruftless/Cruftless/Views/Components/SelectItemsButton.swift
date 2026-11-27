import CruftlessCore
import SwiftUI

/// The leading footer action on every Detail screen with a child listing; it turns selection mode on and off.
struct SelectItemsButton: View {
    let location: TrackedLocation
    let model: AppModel

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var isSelecting: Bool {
        model.isSelecting(in: location)
    }

    var body: some View {
        Group {
            if isSelecting {
                Button("Cancel", action: toggle)
                    .keyboardShortcut(.cancelAction)
                    .accessibilityLabel("Cancel selection in \(location.title)")
            } else {
                Button(action: toggle) {
                    Label("Select Items", systemImage: "checklist")
                }
                .accessibilityLabel("Select Items in \(location.title)")
            }
        }
        .disabled(model.isDeleting)
        .buttonStyle(.glass)
        .controlSize(.large)
        .accessibilityIdentifier("cleanup.select-items.\(location.id)")
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : .snappy(duration: 0.2)) {
            model.toggleSelectionMode(for: location)
        }
    }
}
