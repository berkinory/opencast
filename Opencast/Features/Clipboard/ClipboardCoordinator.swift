import AppKit

@MainActor
final class ClipboardCoordinator {
    private let store: ClipboardStore
    private let palette: PaletteViewModel
    private let previousApplication: () -> NSRunningApplication?
    private let hidePalette: (Bool) -> Void
    private let pasteKeepingOpen: (ClipboardItem, ClipboardStore) -> Bool
    private let confirmDeleteAll: (@escaping () -> Void) -> Void

    init(
        store: ClipboardStore,
        palette: PaletteViewModel,
        previousApplication: @escaping () -> NSRunningApplication?,
        hidePalette: @escaping (Bool) -> Void,
        pasteKeepingOpen: @escaping (ClipboardItem, ClipboardStore) -> Bool,
        confirmDeleteAll: @escaping (@escaping () -> Void) -> Void
    ) {
        self.store = store
        self.palette = palette
        self.previousApplication = previousApplication
        self.hidePalette = hidePalette
        self.pasteKeepingOpen = pasteKeepingOpen
        self.confirmDeleteAll = confirmDeleteAll
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

    func deleteAll(onConfirmed: @escaping () -> Void) {
        confirmDeleteAll { [weak self] in
            self?.store.clearAll()
            onConfirmed()
        }
    }

    private func select(_ item: ClipboardItem) {
        palette.selection = store.rowIndex(of: item, in: palette.query) ?? 0
    }
}
