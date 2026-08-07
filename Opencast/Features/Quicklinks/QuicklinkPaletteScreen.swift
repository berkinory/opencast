import SwiftUI

@MainActor
struct QuicklinkPaletteScreen: PaletteScreen {
    let items: [Quicklink]
    let selection: Int
    let scrollIntent: ListScrollIntent?
    let core: AppCore
    let favorites: FavoritesStore
    let onSelect: (Int) -> Void
    let onOpenActions: () -> Void
    let onToggleFavorite: (Quicklink) -> Void
    let onTogglePinned: (Quicklink) -> Void

    var itemCount: Int { items.count }

    var selectedItem: Quicklink? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    var actionsContent: PopoverMenuContent? {
        guard let selectedItem else { return nil }
        return QuicklinkActionsMenu.content(
            quicklink: selectedItem,
            core: core,
            favorites: favorites,
            onToggleFavorite: { onToggleFavorite(selectedItem) },
            onTogglePinned: { onTogglePinned(selectedItem) }
        )
    }

    var body: some View {
        QuicklinkSearchView(
            results: items,
            selectedID: selectedItem?.id,
            scrollIntent: scrollIntent,
            onSelect: select,
            onActivate: activate,
            onActions: openActions
        )
    }

    @discardableResult
    func activate() -> Bool {
        guard let selectedItem else {
            core.createQuicklink()
            return true
        }
        core.openQuicklink(selectedItem)
        return true
    }

    @discardableResult
    func copy() -> Bool {
        guard let selectedItem else { return false }
        core.copyQuicklink(selectedItem)
        return true
    }

    private func select(_ item: Quicklink) {
        onSelect(items.firstIndex(of: item) ?? 0)
    }

    private func activate(_ item: Quicklink) {
        select(item)
        core.openQuicklink(item)
    }

    private func openActions(_ item: Quicklink) {
        guard let index = items.firstIndex(of: item) else { return }
        onSelect(index)
        onOpenActions()
    }
}
