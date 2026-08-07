import Foundation

@MainActor
final class QuicklinkCoordinator {
    private let store: QuicklinkStore
    private let settings: AppSettings
    private let palette: PaletteViewModel
    private let favorites: FavoritesStore
    private let hidePalette: (Bool) -> Void
    private let chooseTarget: (@escaping (String) -> Void) -> Void

    init(
        store: QuicklinkStore,
        settings: AppSettings,
        palette: PaletteViewModel,
        favorites: FavoritesStore,
        hidePalette: @escaping (Bool) -> Void,
        chooseTarget: @escaping (@escaping (String) -> Void) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.palette = palette
        self.favorites = favorites
        self.hidePalette = hidePalette
        self.chooseTarget = chooseTarget
    }

    func create() {
        guard settings.quicklinksEnabled else { return }
        palette.enterSubscreen(.quicklinkEditor)
    }

    func edit(_ quicklink: Quicklink) {
        guard settings.quicklinksEnabled else { return }
        palette.enterSubscreen(.quicklinkEditor)
        palette.quicklinkEditingID = quicklink.id
        palette.quicklinkEditorReturnsToSearch = true
    }

    func search() {
        guard settings.quicklinksEnabled else { return }
        palette.enterSubscreen(.quicklinks)
    }

    func exitEditor() {
        if palette.quicklinkEditorReturnsToSearch {
            palette.mode = .quicklinks
            palette.query = ""
            palette.selection = 0
            palette.quicklinkEditingID = nil
            palette.quicklinkEditorReturnsToSearch = false
            palette.focusToken = UUID()
            palette.resetToken = UUID()
        } else {
            palette.returnToLauncher()
        }
    }

    func chooseTarget(completion: @escaping (String) -> Void) {
        chooseTarget(completion)
    }

    func open(_ quicklink: Quicklink) {
        guard AppLauncher.open(quicklink) else {
            palette.postFeedback("Could not open quicklink", tone: .error)
            return
        }
        hidePalette(false)
    }

    func copy(_ quicklink: Quicklink) {
        Paster.copyString(quicklink.link)
        palette.postFeedback("Copied link")
    }

    func togglePinned(_ quicklink: Quicklink) {
        do {
            try store.togglePinned(quicklink)
        } catch {
            palette.postFeedback("Could not save quicklink", tone: .error)
            return
        }
        if palette.mode == .quicklinks {
            palette.selection = store.rowIndex(of: quicklink, in: palette.query) ?? 0
        }
    }

    func duplicate(_ quicklink: Quicklink) {
        do {
            _ = try store.duplicate(quicklink)
            palette.postFeedback("Duplicated quicklink")
        } catch {
            palette.postFeedback("Could not duplicate quicklink", tone: .error)
        }
    }

    func delete(_ quicklink: Quicklink) {
        do {
            try store.delete(quicklink)
        } catch {
            palette.postFeedback("Could not delete quicklink", tone: .error)
            return
        }
        favorites.remove(quicklink)
        palette.selection = 0
        palette.postFeedback("Deleted quicklink")
    }
}
