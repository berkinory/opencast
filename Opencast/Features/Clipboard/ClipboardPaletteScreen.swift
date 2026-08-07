import SwiftUI

struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

@MainActor
struct ClipboardPaletteScreen: PaletteScreen {
    let items: [ClipboardItem]
    let selection: Int
    let scrollIntent: ListScrollIntent?
    let store: ClipboardStore
    let core: AppCore
    let pasteTarget: PasteTarget?
    let followKey: ClipFollowKey
    let isQueryEmpty: Bool
    let onSelect: (Int) -> Void
    let onFollow: (Int?) -> Void
    let onOpenActions: () -> Void
    let onFeedback: (String) -> Void

    var selectedItem: ClipboardItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    var itemCount: Int { items.count }

    var actionsContent: PopoverMenuContent? {
        guard let selectedItem else { return nil }
        return ClipboardActionsMenu.content(
            item: selectedItem,
            core: core,
            target: pasteTarget,
            onFeedback: onFeedback
        )
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyResults(text: "Clipboard history is empty")
            } else {
                PaletteDetailLayout(
                    listWidth: Theme.Size.clipboardListWidth,
                    detailTitle: "Preview",
                    sidebar: {
                        ClipboardList(
                            results: items,
                            selectedID: selectedItem?.id,
                            scrollIntent: scrollIntent,
                            onSelect: select,
                            onActivate: activate,
                            onActions: openActions
                        )
                    },
                    detail: {
                        ClipboardPreview(item: selectedItem)
                    },
                    metadata: {
                        if let selectedItem {
                            ClipboardMetadata(
                                item: selectedItem,
                                imageURL: store.imageURL(for: selectedItem)
                            )
                        }
                    }
                )
            }
        }
        .onChange(of: followKey) { old, new in
            guard old.id != nil else { return }
            let movedIndex =
                isQueryEmpty && old.id != new.id
                ? new.id.flatMap { id in items.firstIndex(where: { $0.id == id }) }
                : nil
            onFollow(movedIndex)
        }
    }

    @discardableResult
    func activate() -> Bool {
        guard let selectedItem else { return false }
        core.paste(selectedItem)
        return true
    }

    @discardableResult
    func copy() -> Bool {
        guard let selectedItem else { return false }
        core.copyToClipboard(selectedItem)
        return true
    }

    @discardableResult
    func delete() -> Bool {
        guard let selectedItem else { return false }
        core.deleteClipboardEntry(selectedItem)
        onFeedback("Deleted entry")
        return true
    }

    @discardableResult
    func togglePinned() -> Bool {
        guard let selectedItem else { return false }
        core.togglePinnedClip(selectedItem)
        return true
    }

    private func select(_ item: ClipboardItem) {
        onSelect(items.firstIndex(of: item) ?? 0)
    }

    private func activate(_ item: ClipboardItem) {
        select(item)
        core.paste(item)
    }

    private func openActions(_ item: ClipboardItem) {
        guard let index = items.firstIndex(of: item) else { return }
        onSelect(index)
        onOpenActions()
    }
}
