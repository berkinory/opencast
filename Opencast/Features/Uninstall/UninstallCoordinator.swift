import Foundation

@MainActor
final class UninstallCoordinator {
    private let session: UninstallSession
    private let palette: PaletteViewModel
    private let appIndex: AppIndex
    private let favorites: FavoritesStore
    private let visibility: VisibilityStore
    private let ranking: LauncherRankingStore
    private let hotKeys: HotKeyManager
    private let hidePalette: (Bool) -> Void
    private let confirm: (String, String, String) -> Bool

    init(
        session: UninstallSession,
        palette: PaletteViewModel,
        appIndex: AppIndex,
        favorites: FavoritesStore,
        visibility: VisibilityStore,
        ranking: LauncherRankingStore,
        hotKeys: HotKeyManager,
        hidePalette: @escaping (Bool) -> Void,
        confirm: @escaping (String, String, String) -> Bool
    ) {
        self.session = session
        self.palette = palette
        self.appIndex = appIndex
        self.favorites = favorites
        self.visibility = visibility
        self.ranking = ranking
        self.hotKeys = hotKeys
        self.hidePalette = hidePalette
        self.confirm = confirm
    }

    func begin(_ app: AppEntry) {
        guard app.kind == .application,
            app.url.standardizedFileURL.path != Bundle.main.bundleURL.standardizedFileURL.path,
            AppLeftovers.canUninstall(url: app.url, bundleID: app.bundleID)
        else { return }
        session.begin(app: app)
        palette.enterSubscreen(.uninstall)
    }

    func cancel() {
        session.end()
        palette.returnToLauncher()
    }

    func remove(permanently: Bool = false) {
        guard let app = session.target, !session.checkedItems.isEmpty,
            session.phase == .selecting
        else { return }
        let targets = session.checkedItems
        let bundlePath = app.url.resolvingSymlinksInPath().path
        let removesBundle = targets.contains { $0.url.path == bundlePath }
        if permanently {
            let message = targets.count == 1
                ? "Permanently delete 1 item?"
                : "Permanently delete \(targets.count) items?"
            guard confirm(
                message,
                "“\(app.name)” and the files you checked will be erased immediately. This can’t be undone.",
                "Delete")
            else { return }
        }
        Task { [weak self] in
            guard let self else { return }
            let outcome = await session.remove(permanently: permanently)
            if removesBundle, !outcome.failures.contains(where: { $0.url.path == bundlePath }) {
                forget(app)
            }
            await appIndex.refresh()
        }
    }

    func exit() {
        switch session.phase {
        case .selecting: cancel()
        case .removing: break
        case .done: finish()
        }
    }

    func finish() {
        session.end()
        palette.prepare(mode: .launcher)
    }

    func setSort(_ sort: UninstallSort) {
        session.setSort(sort)
        palette.selection = 0
    }

    func reveal(_ item: LeftoverItem) {
        hidePalette(false)
        AppLauncher.showInFinder(item.url)
    }

    private func forget(_ app: AppEntry) {
        if favorites.isFavorite(app) { favorites.toggle(app) }
        visibility.setItemVisible(true, for: app)
        ranking.reset(itemKey: app.preferenceKey)
        if let action = app.hotKeyAction { hotKeys.setShortcut(nil, for: action) }
    }
}
