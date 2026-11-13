import CruftlessCore
import SwiftUI

/// One plan item in Review, with its live run state while a plan executes.
struct ReviewItemRow: View {
    let item: DeletionTarget
    let state: DeletionItemRunState?
    let phaseDetail: String?
    let showsActionLabel: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            if let state {
                RunStateIcon(state: state)
                    .frame(width: 16, height: 16)
                    .padding(.top, 1)
            }
            VStack(alignment: .leading, spacing: 3) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(item.name)
                        .font(.system(size: 12, weight: .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Spacer(minLength: 8)

                    Text(ByteFormatter.format(item.reclaimableBytes))
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(.secondary)
                }

                if case let .androidAVDDelete(request) = item {
                    Text(request.identity.directory.path(percentEncoded: false))
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                caption(for: item, state: state)

                if showsActionLabel, state == nil || state == .pending {
                    Text(Self.actionLabel(for: item))
                        .font(.system(size: 11, weight: .semibold))
                }
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .opacity(state.map(Self.opacity(for:)) ?? 1)
        .accessibilityElement(children: .combine)
        .accessibilityValue(state.map(Self.accessibilityText(for:)) ?? "")
    }

    @ViewBuilder
    private func caption(for item: DeletionTarget, state: DeletionItemRunState?) -> some View {
        let text: (String, Color)? = switch state {
        case .active: (phaseDetail ?? "In progress…", .secondary)
        case let .done(freed): ("Freed \(ByteFormatter.format(freed))", .secondary)
        case let .failed(reason): (reason, .red)
        case let .skipped(reason): (reason, .secondary)
        case .pending, nil: nil
        }
        Text(text?.0 ?? item.consequence)
            .font(.system(size: 11))
            .foregroundStyle(text?.1 ?? (item.isFlagged ? DesignTokens.tierColor(for: .irreversible) : .secondary))
            .frame(maxWidth: .infinity, alignment: .leading)
            .fixedSize(horizontal: false, vertical: true)
    }

    private static func opacity(for state: DeletionItemRunState) -> Double {
        switch state {
        case .pending, .active, .failed: 1
        case .done, .skipped: 0.65
        }
    }

    private static func accessibilityText(for state: DeletionItemRunState) -> String {
        switch state {
        case .pending: "Waiting"
        case .active: "In progress"
        case .done: "Done"
        case .failed: "Failed"
        case .skipped: "Skipped"
        }
    }

    private static func actionLabel(for target: DeletionTarget) -> String {
        switch target {
        case let .path(_, _, _, _, tier, _, _, _): tier == .regen ? "Clear" : "Delete"
        case let .simulatorErase(_, _, booted, _, _): booted ? "Shut Down and Erase" : "Erase"
        case let .simulatorDelete(_, _, booted, _, _): booted ? "Shut Down and Delete" : "Delete"
        case .xctestSimulatorDelete: "Delete Test Simulator"
        case .runtimeDelete: "Delete Runtime"
        case .androidAVDDelete: "Delete Device"
        }
    }
}
