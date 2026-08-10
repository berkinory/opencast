import SwiftUI

struct EmojiGridSection: Identifiable {
    let title: String
    let entries: [EmojiEntry]
    let start: Int

    var id: String { title }
}

enum EmojiGrid {
    static let columns = 8

    @MainActor
    static func sections(
        query: String, index: EmojiIndex, frequent: FrequentEmojiStore
    ) -> [EmojiGridSection] {
        var sections: [EmojiGridSection] = []
        var start = 0
        func append(_ title: String, _ entries: [EmojiEntry]) {
            guard !entries.isEmpty else { return }
            sections.append(EmojiGridSection(title: title, entries: entries, start: start))
            start += entries.count
        }
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            append("Frequently Used", frequent.top().compactMap(index.entry(for:)))
            for section in index.categorySections {
                append(section.category.title, section.entries)
            }
        } else {
            append("Results", index.search(query))
        }
        return sections
    }
}

struct EmojiGridView: View {
    let sections: [EmojiGridSection]
    let selection: Int
    let tone: EmojiSkinTone
    let scroll: ListScrollIntent
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void

    var body: some View {
        PaletteGridLayout(
            sections: sections.map {
                PaletteGridSection(id: $0.id, title: $0.title, items: $0.entries)
            },
            columns: EmojiGrid.columns,
            selection: selection,
            scroll: scroll,
            columnSpacing: 0,
            rowSpacing: 0,
            minimumCellHeight: Theme.Size.emojiCell,
            contentInsets: EdgeInsets(
                top: Theme.Spacing.xs,
                leading: Theme.Spacing.md,
                bottom: Theme.Spacing.md,
                trailing: Theme.Spacing.md
            ),
            onSelect: onSelect,
            onActivate: onActivate,
            onActions: onActions
        ) { entry, selected, hovered in
            EmojiCell(
                glyph: entry.display(tone: tone), selected: selected, hovered: hovered)
        } footer: {
            EmptyView()
        }
    }
}

private struct EmojiCell: View {
    let glyph: String
    let selected: Bool
    let hovered: Bool

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Text(glyph)
            .font(Theme.Typography.emojiGlyph)
            .frame(maxWidth: .infinity)
            .frame(height: Theme.Size.emojiCell)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(fill)
            )
    }
}

@MainActor
enum EmojiActionsMenu {
    static func content(entry: EmojiEntry, coordinator: EmojiCoordinator, target: PasteTarget?)
        -> PopoverMenuContent
    {
        PopoverMenuContent(
            header: entry.displayName,
            items: [
                PopoverMenuItem(
                    title: target?.pasteTitle ?? "Paste",
                    icon: .paste(target, fallback: "doc.on.clipboard"), shortcut: "↵"
                ) {
                    coordinator.paste(entry)
                },
                PopoverMenuItem(
                    title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵"
                ) {
                    coordinator.copy(entry)
                },
                PopoverMenuItem(
                    title: "Paste & Keep Window Open", icon: .paste(target, fallback: "macwindow")
                ) {
                    coordinator.pasteAndKeepOpen(entry)
                },
            ]
        )
    }
}
