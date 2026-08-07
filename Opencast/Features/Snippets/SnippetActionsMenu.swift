import SwiftUI

@MainActor
enum SnippetActionsMenu {
    static func content(
        snippet: Snippet, coordinator: SnippetCoordinator, target: PasteTarget?,
        onTogglePinned: (() -> Void)? = nil
    ) -> PopoverMenuContent {
        PopoverMenuContent(
            header: snippet.name,
            items: [
                PopoverMenuItem(
                    title: target?.pasteTitle ?? "Paste",
                    icon: .paste(target, fallback: "doc.on.clipboard"),
                    shortcut: "↵"
                ) {
                    coordinator.paste(snippet)
                },
                PopoverMenuItem(title: "Copy to Clipboard", systemImage: "doc.on.doc", shortcut: "⌘↵") {
                    coordinator.copy(snippet)
                },
                PopoverMenuItem(
                    title: snippet.isPinned ? "Unpin Snippet" : "Pin Snippet",
                    systemImage: snippet.isPinned ? "pin.slash" : "pin",
                    shortcut: "⌘P"
                ) {
                    if let onTogglePinned { onTogglePinned() } else { coordinator.togglePinned(snippet) }
                },
                PopoverMenuItem(title: "Duplicate Snippet", systemImage: "plus.square.on.square") {
                    coordinator.duplicate(snippet)
                },
                PopoverMenuItem(title: "Edit Snippet", systemImage: "pencil") {
                    coordinator.edit(snippet)
                },
                PopoverMenuItem(
                    title: "Delete Snippet", systemImage: "trash", isDestructive: true
                ) {
                    coordinator.delete(snippet)
                },
            ]
        )
    }
}
