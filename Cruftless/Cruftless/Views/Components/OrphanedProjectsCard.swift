import CruftlessCore
import SwiftUI

/// The Derived Data suggestion that selects every folder whose project is gone, for Select Items and Review.
struct OrphanedProjectsCard: View {
    let suggestion: OrphanedProjectsSuggestion
    let isDisabled: Bool
    let onSelect: () -> Void

    var body: some View {
        HStack(spacing: PopoverMetrics.rowSpacing) {
            Image(systemName: "questionmark.folder")
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.orange)
                .frame(width: PopoverMetrics.iconSlot)

            VStack(alignment: .leading, spacing: 1) {
                Text("Orphaned projects · \(suggestion.count) · \(ByteFormatter.format(suggestion.reclaimableBytes))")
                    .font(.system(size: 13))
                    .monospacedDigit()
                    .lineLimit(1)
                Text("Their projects were deleted or moved.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            Button("Select", action: onSelect)
                .buttonStyle(.glass)
                .controlSize(.small)
                .disabled(isDisabled)
                .accessibilityLabel("Select \(suggestion.count) orphaned projects")
                .accessibilityIdentifier("detail.orphaned-projects.select")
        }
        .padding(10)
        .glassEffect(in: .rect(cornerRadius: 12))
        .accessibilityElement(children: .combine)
    }
}

/// A Derived Data row's caption: the project it was built from.
struct DerivedDataWorkspaceCaption: View {
    let workspace: DerivedDataWorkspace?

    var body: some View {
        if let path = workspace?.path {
            Text(Naming.abbreviatingHome(in: path))
                .foregroundStyle(.secondary)
                .truncationMode(.middle)
                .help(path)
        }
    }
}

extension DerivedDataWorkspace {
    /// The Select Items subtitle for a Derived Data row, or `nil` when the folder records no project.
    var selectionSubtitle: String? {
        path.map { Naming.abbreviatingHome(in: $0) }
    }
}

#if DEBUG
    import CruftlessFixtures

    #Preview("Orphaned projects card") {
        VStack(spacing: 8) {
            if let suggestion = OrphanedProjectsSuggestion(
                children: PreviewFixtures.derivedDataChildren,
                protectedPaths: .default
            ) {
                OrphanedProjectsCard(suggestion: suggestion, isDisabled: false) {}
                OrphanedProjectsCard(suggestion: suggestion, isDisabled: true) {}
            }
        }
        .padding(6)
        .frame(width: PopoverMetrics.width)
    }

    #Preview("Workspace captions") {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(PreviewFixtures.derivedDataChildren) { child in
                DerivedDataWorkspaceCaption(workspace: child.workspace)
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
        }
        .padding()
        .frame(width: PopoverMetrics.width)
    }
#endif
