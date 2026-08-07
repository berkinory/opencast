import SwiftUI

@MainActor
enum QuicklinkActionsMenu {
    static func content(
        quicklink: Quicklink, coordinator: QuicklinkCoordinator, favorites: FavoritesStore,
        onToggleFavorite: @escaping () -> Void,
        onTogglePinned: (() -> Void)? = nil
    ) -> PopoverMenuContent {
        let favoriteItem =
            favorites.isFavorite(quicklink)
            ? PopoverMenuItem(
                title: "Remove from Favorites", systemImage: "star.slash", shortcut: "⌘F",
                action: onToggleFavorite)
            : PopoverMenuItem(
                title: "Add to Favorites", systemImage: "star", shortcut: "⌘F",
                action: onToggleFavorite)
        let pinnedItem =
            quicklink.isPinned
            ? PopoverMenuItem(
                title: "Unpin Quicklink", systemImage: "pin.slash", shortcut: "⌘P"
            ) {
                if let onTogglePinned {
                    onTogglePinned()
                } else {
                    coordinator.togglePinned(quicklink)
                }
            }
            : PopoverMenuItem(
                title: "Pin Quicklink", systemImage: "pin", shortcut: "⌘P"
            ) {
                if let onTogglePinned {
                    onTogglePinned()
                } else {
                    coordinator.togglePinned(quicklink)
                }
            }
        return PopoverMenuContent(
            header: quicklink.name,
            items: [
                PopoverMenuItem(
                    title: "Open Quicklink", systemImage: "arrow.up.right", shortcut: "↵"
                ) {
                    coordinator.open(quicklink)
                },
                favoriteItem,
                pinnedItem,
                PopoverMenuItem(title: "Copy Link", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                    coordinator.copy(quicklink)
                },
                PopoverMenuItem(title: "Duplicate Quicklink", systemImage: "plus.square.on.square") {
                    coordinator.duplicate(quicklink)
                },
                PopoverMenuItem(title: "Edit Quicklink", systemImage: "pencil") {
                    coordinator.edit(quicklink)
                },
                PopoverMenuItem(
                    title: "Delete Quicklink", systemImage: "trash", isDestructive: true
                ) {
                    coordinator.delete(quicklink)
                },
            ]
        )
    }
}
