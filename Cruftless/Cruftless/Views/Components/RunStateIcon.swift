import CruftlessCore
import SwiftUI

/// The leading status mark for one item while a plan runs.
struct RunStateIcon: View {
    let state: DeletionItemRunState

    var body: some View {
        switch state {
        case .pending:
            Image(systemName: "circle")
                .foregroundStyle(.tertiary)
        case .active:
            ProgressView().controlSize(.small)
        case .done:
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed:
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(.red)
        case .skipped:
            Image(systemName: "minus.circle")
                .foregroundStyle(.secondary)
        }
    }
}

#if DEBUG
    #Preview("Run states") {
        VStack(alignment: .leading, spacing: 8) {
            RunStateIcon(state: .pending)
            RunStateIcon(state: .active)
            RunStateIcon(state: .done(freedBytes: 1))
            RunStateIcon(state: .failed(reason: "x"))
            RunStateIcon(state: .skipped(reason: "x"))
        }
        .padding()
    }
#endif
