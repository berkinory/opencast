import SwiftUI

struct UninstallList: View {
    let items: [LeftoverItem]
    let selection: Int
    let isChecked: (LeftoverItem) -> Bool
    let appIcon: NSImage?
    let scroll: ListScrollIntent
    let onSelect: (Int) -> Void
    let onToggle: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        PaletteListLayout(
            scroll: scroll,
            scrollTarget: items.indices.contains(selection) ? items[selection].id : nil
        ) {
            LazyVStack(spacing: 0) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    UninstallRow(
                        item: item,
                        checked: isChecked(item),
                        selected: index == selection,
                        icon: item.kind == .bundle ? appIcon : nil
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        onSelect(index)
                        onToggle(index)
                    }
                    .onRightClick { onActions(index) }
                }
            }
            .padding(.horizontal, Theme.Spacing.md)
            .padding(.top, Theme.Spacing.xs)
            .padding(.bottom, Theme.Spacing.md)
            .hideNativeScrollers()
            .resetNativeScrollToTop(id: scroll.kind == .top ? scroll.id : nil)
        }
    }
}

struct UninstallStatusLine: View {
    let checkedCount: Int
    let totalCount: Int
    let checkedSize: Int64

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            Text("\(checkedCount) of \(totalCount) \(totalCount == 1 ? "file" : "files") selected")
            if checkedSize > 0 {
                Text(UninstallFormat.size(checkedSize)).monospacedDigit()
            }
        }
        .font(Theme.Typography.sectionHeader)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, Theme.Spacing.md * 2)
        .padding(.bottom, Theme.Spacing.sm)
    }
}

struct UninstallProgressView: View {
    let name: String
    let permanently: Bool

    var body: some View {
        VStack(spacing: Theme.Spacing.xl) {
            ProgressView().controlSize(.large)
            Text(permanently ? "Deleting \(name)…" : "Moving \(name) to the Trash…")
                .font(Theme.Typography.rowTitle)
                .foregroundStyle(Theme.Colors.textSecondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

struct UninstallSummaryView: View {
    let name: String
    let outcome: UninstallOutcome

    private var title: String {
        guard outcome.removedCount > 0 else { return "Nothing was removed" }
        let items = "\(outcome.removedCount) \(outcome.removedCount == 1 ? "item" : "items")"
        return outcome.permanently ? "Deleted \(items)" : "Moved \(items) to the Trash"
    }

    var body: some View {
        VStack(spacing: Theme.Spacing.lg) {
            Image(systemName: outcome.failures.isEmpty ? "checkmark.circle" : "exclamationmark.triangle")
                .font(.largeTitle)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(outcome.failures.isEmpty ? Color.primary : Color.red)
            VStack(spacing: Theme.Spacing.xs) {
                Text("\(name) — \(title)").font(Theme.Typography.rowTitle)
                if outcome.reclaimed > 0 {
                    Text("\(UninstallFormat.size(outcome.reclaimed)) reclaimed")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .monospacedDigit()
                }
                if outcome.removedCount > 0, !outcome.permanently {
                    Text("Recoverable from the Trash")
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
            }
            if !outcome.failures.isEmpty { failureList }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, Theme.Spacing.xxl)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var failureList: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
            Text(
                outcome.failures.count == 1
                    ? "1 item couldn’t be removed — it may need an administrator, or still be in use."
                    : "\(outcome.failures.count) items couldn’t be removed — they may need an administrator, or still be in use."
            )
            .font(Theme.Typography.rowTrailing)
            .foregroundStyle(Theme.Colors.textSecondary)
            ForEach(outcome.failures) { failure in
                Text(failure.displayPath)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
                .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
        )
    }
}

struct UninstallSortButton: View {
    let sort: UninstallSort
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: sort.systemImage).symbolRenderingMode(.hierarchical)
                Text(sort.title)
                Image(systemName: "chevron.down").font(Theme.Typography.keyCap)
            }
            .font(Theme.Typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 28)
            .contentShape(Capsule())
            .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .fixedSize()
    }
}

struct UninstallContextPill: View {
    let name: String
    let icon: NSImage?

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            if let icon {
                Image(nsImage: icon).resizable()
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
            } else {
                Image(systemName: "trash")
                    .font(Theme.Typography.menuIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
            }
            Text("Uninstall \(name)")
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.menuButton)
        .frosted(in: Capsule())
    }
}

private struct UninstallRow: View {
    let item: LeftoverItem
    let checked: Bool
    let selected: Bool
    let icon: NSImage?
    private var directory: String {
        (item.url.deletingLastPathComponent().path as NSString).abbreviatingWithTildeInPath
    }

    private var trailingSymbol: String {
        if item.url.pathExtension == "app" { return "app.badge" }
        return item.url.pathExtension.isEmpty ? "folder" : "doc"
    }

    var body: some View {
        PaletteRow(
            selected: selected,
            leading: {
                UninstallCheckbox(checked: checked)
            },
            content: {
                Text(item.url.lastPathComponent)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
                    .foregroundStyle(checked ? Color.primary : Theme.Colors.textSecondary)
                Text(directory)
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.textTertiary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            },
            trailing: {
                if let size = item.size {
                    Text(UninstallFormat.size(size))
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Group {
                    if let icon {
                        Image(nsImage: icon).resizable()
                    } else {
                        Image(systemName: trailingSymbol)
                            .font(Theme.Typography.menuIcon)
                            .symbolRenderingMode(.hierarchical)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            }
        )
    }
}

private struct UninstallCheckbox: View {
    let checked: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: Theme.Radius.checkbox, style: .continuous)
        return ZStack {
            if checked {
                shape.fill(Color.primary.opacity(0.85))
                Image(systemName: "checkmark")
                    .font(Theme.Typography.keyCap.weight(.bold))
                    .foregroundStyle(Theme.Colors.textOnPrimary.opacity(0.8))
            } else {
                shape.strokeBorder(Theme.Colors.border, lineWidth: 1)
            }
        }
        .frame(width: Theme.Size.checkbox, height: Theme.Size.checkbox)
    }
}

@MainActor
enum UninstallFormat {
    private static let formatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter
    }()

    static func size(_ bytes: Int64) -> String { formatter.string(fromByteCount: bytes) }
}

@MainActor
enum UninstallActionsMenu {
    static func content(
        session: UninstallSession, visible: [LeftoverItem], selection: Int,
        coordinator: UninstallCoordinator
    ) -> PopoverMenuContent {
        let name = session.target?.name ?? "Application"
        var items: [PopoverMenuItem] = []
        if !session.checkedItems.isEmpty {
            items.append(
                PopoverMenuItem(
                    title: "Uninstall Application", systemImage: "trash", shortcut: "↵", isDestructive: true
                ) { coordinator.remove() }
            )
            items.append(
                PopoverMenuItem(
                    title: "Permanently Delete…", systemImage: "trash.slash", shortcut: "⇧⌘⌫", isDestructive: true
                ) { coordinator.remove(permanently: true) }
            )
        }
        if visible.indices.contains(selection) {
            let item = visible[selection]
            items.append(
                PopoverMenuItem(title: "Show in Finder", systemImage: "folder", shortcut: "⌘↵") {
                    coordinator.reveal(item)
                }
            )
        }
        items.append(
            PopoverMenuItem(title: "Cancel", systemImage: "xmark", shortcut: "⎋") {
                coordinator.cancel()
            }
        )
        return PopoverMenuContent(header: "Uninstall \(name)", items: items)
    }

    static func sortContent(
        session: UninstallSession, onSelect: @escaping (UninstallSort) -> Void
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: "Sort",
            items: UninstallSort.allCases.map { sort in
                PopoverMenuItem(
                    title: sort.title,
                    systemImage: sort == session.sort ? "checkmark" : sort.systemImage
                ) { onSelect(sort) }
            }
        )
    }
}
