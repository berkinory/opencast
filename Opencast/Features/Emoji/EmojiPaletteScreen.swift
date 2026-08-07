import SwiftUI

@MainActor
struct EmojiPaletteScreen: PaletteScreen {
    let sections: [EmojiGridSection]
    let selection: Int
    let tone: EmojiSkinTone
    let scroll: EmojiScrollIntent
    let isLoaded: Bool
    let core: AppCore
    let pasteTarget: PasteTarget?
    let onSelect: (Int) -> Void
    let onOpenActions: () -> Void

    private var items: [EmojiEntry] { sections.flatMap(\.entries) }

    var itemCount: Int { items.count }

    var selectedItem: EmojiEntry? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    var actionsContent: PopoverMenuContent? {
        guard let selectedItem else { return nil }
        return EmojiActionsMenu.content(entry: selectedItem, core: core, target: pasteTarget)
    }

    var body: some View {
        Group {
            if !isLoaded {
                EmptyResults(text: "Loading emoji…")
            } else if sections.isEmpty {
                EmptyResults(text: "No emoji found")
            } else {
                EmojiGridView(
                    sections: sections,
                    selection: selection,
                    tone: tone,
                    scroll: scroll,
                    onSelect: onSelect,
                    onActivate: { _ = activate() },
                    onActions: { index in
                        onSelect(index)
                        onOpenActions()
                    }
                )
            }
        }
    }

    @discardableResult
    func activate() -> Bool {
        guard let selectedItem else { return false }
        core.pasteEmoji(selectedItem)
        return true
    }

    @discardableResult
    func copy() -> Bool {
        guard let selectedItem else { return false }
        core.copyEmoji(selectedItem)
        return true
    }

    @discardableResult
    func pasteKeepingOpen() -> Bool {
        guard let selectedItem else { return false }
        core.pasteEmojiKeepingWindowOpen(selectedItem)
        return true
    }

    func selectionAfterMovingRow(_ direction: Int) -> Int {
        let geometry = EmojiGridGeometry(
            counts: sections.map(\.entries.count), columns: EmojiGrid.columns)
        return direction > 0 ? geometry.down(from: selection) : geometry.up(from: selection)
    }
}
