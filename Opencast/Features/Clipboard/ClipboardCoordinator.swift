import AppKit

@MainActor
final class ClipboardCoordinator {
    private let imagePreview = ClipboardImagePreview()
    private let store: ClipboardStore
    private let palette: PaletteViewModel
    private let previousApplication: () -> NSRunningApplication?
    private let hidePalette: (Bool) -> Void
    private let pasteKeepingOpen: (ClipboardItem, ClipboardStore) -> Bool

    init(
        store: ClipboardStore,
        palette: PaletteViewModel,
        previousApplication: @escaping () -> NSRunningApplication?,
        hidePalette: @escaping (Bool) -> Void,
        pasteKeepingOpen: @escaping (ClipboardItem, ClipboardStore) -> Bool
    ) {
        self.store = store
        self.palette = palette
        self.previousApplication = previousApplication
        self.hidePalette = hidePalette
        self.pasteKeepingOpen = pasteKeepingOpen
    }

    func paste(_ item: ClipboardItem) {
        let previous = previousApplication()
        hidePalette(false)
        if Paster.paste(item, store: store, previousApp: previous) {
            select(item)
        }
    }

    func pasteAndKeepOpen(_ item: ClipboardItem) {
        if pasteKeepingOpen(item, store) {
            select(item)
        }
    }

    func copy(_ item: ClipboardItem) {
        hidePalette(false)
        if Paster.copy(item, store: store) {
            select(item)
        }
    }

    func revealImage(_ item: ClipboardItem) {
        guard let url = store.imageURL(for: item) else { return }
        hidePalette(false)
        AppLauncher.showInFinder(url)
    }

    func previewImage(_ item: ClipboardItem) {
        guard let url = store.imageURL(for: item) else { return }
        hidePalette(false)
        imagePreview.show(url)
    }

    func revealFile(_ url: URL) {
        hidePalette(false)
        AppLauncher.showInFinder(url)
    }

    func togglePinned(_ item: ClipboardItem) {
        store.togglePinned(item)
        select(item)
        palette.followToken = UUID()
    }

    func delete(_ item: ClipboardItem) {
        store.remove(item)
    }

    func deleteAll(onCleared: () -> Void) {
        guard store.clearHistory() else {
            NSSound.beep()
            return
        }
        onCleared()
    }

    private func select(_ item: ClipboardItem) {
        palette.selection = store.rowIndex(of: item, in: palette.query) ?? 0
    }
}
