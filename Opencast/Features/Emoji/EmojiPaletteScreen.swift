import SwiftUI

@MainActor
struct EmojiPaletteScreen: PaletteScreen {
    let sections: [EmojiGridSection]
    let selection: Int
    let tone: EmojiSkinTone
    let scroll: ListScrollIntent
    let isLoaded: Bool
    let coordinator: EmojiCoordinator
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
        return EmojiActionsMenu.content(
            entry: selectedItem, coordinator: coordinator, target: pasteTarget)
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
                    onActivate: { index in
                        guard items.indices.contains(index) else { return }
                        onSelect(index)
                        coordinator.paste(items[index])
                    },
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
        coordinator.paste(selectedItem)
        return true
    }

    @discardableResult
    func copy() -> Bool {
        guard let selectedItem else { return false }
        coordinator.copy(selectedItem)
        return true
    }

    @discardableResult
    func pasteKeepingOpen() -> Bool {
        guard let selectedItem else { return false }
        coordinator.pasteAndKeepOpen(selectedItem)
        return true
    }

}
