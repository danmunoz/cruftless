import AppKit
import CruftlessCore
import SwiftUI

/// A row's hover-revealed action.
struct RowAction {
    let label: String
    let accessibilityLabel: String
    let isDestructive: Bool
    /// Replaces the label while set, and keeps the hover controls shown.
    let confirmation: String?
    let handler: () -> Void

    init(
        _ label: String,
        isDestructive: Bool = false,
        accessibilityLabel: String? = nil,
        confirmation: String? = nil,
        handler: @escaping () -> Void
    ) {
        self.label = label
        self.confirmation = confirmation
        self.accessibilityLabel = accessibilityLabel ?? label
        self.isDestructive = isDestructive
        self.handler = handler
    }
}

struct PopoverRow<Caption: View>: View {
    let icon: RowIcon?
    var iconFileURL: URL?
    let title: String
    var titleColor: Color = .primary
    var sizeBytes: Int64?
    /// Tint for the inline ⚠ marker that follows the title.
    var flagTint: Color?
    var action: RowAction?
    /// Optional rescan action shown on hover.
    var rescan: (() -> Void)?
    var showsChevron: Bool = false
    /// A location the app cannot delete from (the root-owned dyld cache).
    var isReadOnly: Bool = false
    /// A row for a location that is still being measured: dimmed, with a spinner where its size will go.
    var isPlaceholder: Bool = false
    /// A row whose content could not be read.
    var isUnavailable: Bool = false
    var isOpening: Bool = false
    /// Lets the row grow past the fixed height for a multi-line caption.
    var allowsTallCaption: Bool = false
    var onSelect: (() -> Void)?
    @ViewBuilder var caption: Caption

    @State private var isHovered = false
    @FocusState private var isFocused: Bool
    #if DEBUG
        @State private var previewFocused = false
    #endif

    private var isInteractive: Bool {
        onSelect != nil || action != nil || rescan != nil
    }

    private var isFocusVisible: Bool {
        #if DEBUG
            return isFocused || previewFocused
        #else
            return isFocused
        #endif
    }

    private var contentOpacity: Double {
        isPlaceholder || isUnavailable ? 0.5 : 1
    }

    var body: some View {
        HStack(spacing: PopoverMetrics.rowSpacing) {
            leadingContent
                .selectsRow(onSelect)

            trailingSlot
                .fixedSize(horizontal: true, vertical: false)
                .layoutPriority(2)
                .animation(.snappy(duration: 0.16), value: showsHoverControls)

            chevronColumn
                .selectsRow(onSelect)
        }
        .padding(.horizontal, PopoverMetrics.rowInset)
        .padding(.vertical, 2)
        .frame(height: allowsTallCaption ? nil : PopoverMetrics.rowHeight)
        .frame(minHeight: allowsTallCaption ? PopoverMetrics.rowHeight : nil)
        .background { selectionSurface }
        .contentShape(.rect(cornerRadius: PopoverMetrics.rowCornerRadius))
        .animation(.snappy(duration: 0.16), value: isHovered)
        .onHover { isHovered = $0 }
        .focusable(onSelect != nil)
        .focusEffectDisabled()
        .focused($isFocused)
        .onKeyPress(keys: [.return, .space]) { _ in
            guard let onSelect else { return .ignored }
            onSelect()
            return .handled
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint(accessibilityHint)
        .accessibilityAddTraits(onSelect != nil ? .isButton : [])
        .accessibilityActions {
            if let rescan {
                Button("Rescan", action: rescan)
            }
            if let action {
                Button(action.accessibilityLabel, action: action.handler)
            }
        }
        .contextMenu {
            if let onSelect, showsChevron {
                Button("Show Details", action: onSelect)
            }
            if let rescan {
                Button("Rescan", action: rescan)
            }
            if let action {
                Button(action.accessibilityLabel, role: action.isDestructive ? .destructive : nil, action: action.handler)
            }
        }
    }

    /// Icon, title and caption, plus the space up to the trailing slot.
    private var leadingContent: some View {
        HStack(spacing: PopoverMetrics.rowSpacing) {
            if let icon {
                RowIconView(icon: icon, fileURL: iconFileURL)
                    .frame(width: PopoverMetrics.iconSlot, height: PopoverMetrics.iconSlot)
                    .opacity(isPlaceholder ? 0.5 : contentOpacity)
            }

            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(.system(size: 13))
                        .foregroundStyle(isPlaceholder ? AnyShapeStyle(.secondary) : AnyShapeStyle(titleColor))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .help(title)

                    if let flagTint {
                        RowFlagMarker(tint: flagTint)
                    }
                }

                caption
                    .font(.system(size: 11))
                    .lineLimit(1)
            }
            .layoutPriority(1)
            .opacity(contentOpacity)

            Spacer(minLength: 0)
        }
    }

    private var chevronColumn: some View {
        HStack(spacing: 5) {
            if isOpening {
                ProgressView().controlSize(.mini)
            } else {
                if isReadOnly {
                    Image(systemName: "lock")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                }
                if showsChevron {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .frame(minWidth: PopoverMetrics.chevronColumn, alignment: .trailing)
        .opacity(contentOpacity)
    }

    /// Highlight behind the content, and the tap target for the gaps between its parts.
    private var selectionSurface: some View {
        let shape = RoundedRectangle(cornerRadius: PopoverMetrics.rowCornerRadius, style: .continuous)
        return shape
            .fill(.quaternary.opacity((isHovered && isInteractive) || isFocusVisible ? 1 : 0))
            .overlay {
                shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                    .opacity(isFocusVisible ? 1 : 0)
            }
            .contentShape(shape)
            .onTapGesture {
                onSelect?()
            }
    }

    private var accessibilityHint: String {
        if showsChevron, isReadOnly { return "Opens details. Cleanup is unavailable." }
        if showsChevron { return "Opens details." }
        if isReadOnly, action != nil { return "Locked. Review the risks before cleanup." }
        if isReadOnly { return "Cleanup is unavailable." }
        return ""
    }

    private var showsHoverControls: Bool {
        (isHovered || action?.confirmation != nil) && (action != nil || rescan != nil)
    }

    @ViewBuilder
    private var trailingSlot: some View {
        if isPlaceholder {
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.7)
                .frame(minWidth: PopoverMetrics.sizeColumn, alignment: .trailing)
        } else if showsHoverControls {
            hoverControls
                .transition(.opacity)
        } else {
            Text(sizeBytes.map { ByteFormatter.format($0) } ?? "-")
                .font(.system(size: 13))
                .monospacedDigit()
                .foregroundStyle(.primary)
                .opacity(contentOpacity)
                .frame(minWidth: PopoverMetrics.sizeColumn, alignment: .trailing)
                .selectsRow(onSelect)
                .transition(.opacity)
        }
    }

    private var hoverControls: some View {
        HStack(spacing: 6) {
            if let rescan {
                Button(action: rescan) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 20, height: 20)
                        .glassEffect(.regular.interactive(), in: .circle)
                        .contentShape(.circle)
                }
                .buttonStyle(.plain)
                .help("Rescan \(title)")
                .accessibilityLabel("Rescan \(title)")
            }

            if let action {
                Button(action.confirmation ?? action.label, action: action.handler)
                    .accessibilityLabel(action.accessibilityLabel)
                    .help(action.accessibilityLabel)
                    .buttonStyle(.glass)
                    .controlSize(.small)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(action.isDestructive ? Color.red : .primary)
                    .fixedSize()
            }
        }
        .frame(minWidth: PopoverMetrics.sizeColumn, alignment: .trailing)
    }

    #if DEBUG
        func previewHover(_ hovered: Bool) -> Self {
            var row = self
            row._isHovered = State(initialValue: hovered)
            return row
        }

        func previewFocus(_ focused: Bool) -> Self {
            var row = self
            row._previewFocused = State(initialValue: focused)
            return row
        }
    #endif
}

extension PopoverRow where Caption == EmptyView {
    init(
        icon: RowIcon?,
        iconFileURL: URL? = nil,
        title: String,
        titleColor: Color = .primary,
        sizeBytes: Int64? = nil,
        flagTint: Color? = nil,
        action: RowAction? = nil,
        rescan: (() -> Void)? = nil,
        showsChevron: Bool = false,
        isReadOnly: Bool = false,
        isPlaceholder: Bool = false,
        isUnavailable: Bool = false,
        onSelect: (() -> Void)? = nil
    ) {
        self.init(
            icon: icon,
            iconFileURL: iconFileURL,
            title: title,
            titleColor: titleColor,
            sizeBytes: sizeBytes,
            flagTint: flagTint,
            action: action,
            rescan: rescan,
            showsChevron: showsChevron,
            isReadOnly: isReadOnly,
            isPlaceholder: isPlaceholder,
            isUnavailable: isUnavailable,
            onSelect: onSelect,
            caption: { EmptyView() }
        )
    }
}

/// Renders a `RowIcon` in a 20 pt slot.
struct RowIconView: View {
    let icon: RowIcon
    var fileURL: URL?

    @State private var fileIcon: NSImage?

    var body: some View {
        content
            .task(id: fileURL) {
                await resolveFileIconIfNeeded()
            }
    }

    @ViewBuilder
    private var content: some View {
        switch icon {
        case let .symbol(name):
            Image(systemName: name)
                .font(.system(size: 16))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(.secondary)
        case let .image(name):
            // The catalog asks for `.image("xcode")`, which is not a bundled asset.
            if let bundled = NSImage(named: name) {
                image(bundled)
            } else if let fileIcon {
                image(fileIcon)
            } else {
                Image(systemName: "app.dashed")
                    .font(.system(size: 16))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func image(_ nsImage: NSImage) -> some View {
        Image(nsImage: nsImage)
            .resizable()
            .interpolation(.high)
            .scaledToFit()
            .frame(width: 16, height: 16)
    }

    private func resolveFileIconIfNeeded() async {
        guard case let .image(name) = icon, NSImage(named: name) == nil,
              let fileURL, FileManager.default.fileExists(atPath: fileURL.path(percentEncoded: false)) else {
            fileIcon = nil
            return
        }
        fileIcon = NSWorkspace.shared.icon(forFile: fileURL.path(percentEncoded: false))
    }
}

/// The ⚠ marker for a flagged row, drawn inline after the title.
struct RowFlagMarker: View {
    var tint: Color = .secondary

    var body: some View {
        Image(systemName: "exclamationmark.triangle.fill")
            .font(.system(size: 10))
            .foregroundStyle(tint)
    }
}

private extension View {
    /// Opens the row on a click; applied only to parts that hold no buttons, so one click fires one action.
    func selectsRow(_ onSelect: (() -> Void)?) -> some View {
        contentShape(.rect).onTapGesture { onSelect?() }
    }
}
