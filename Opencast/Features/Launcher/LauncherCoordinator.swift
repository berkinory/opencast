import AppKit

@MainActor
final class LauncherCoordinator {
    private let ranking: LauncherRankingStore
    private let appIndex: AppIndex
    private let settings: AppSettings
    private let palette: PaletteViewModel
    private let snippets: SnippetCoordinator
    private let quicklinks: QuicklinkCoordinator
    private let windowCommands: WindowCommandCoordinator
    private let systemCommands: SystemCommandCoordinator
    private let hidePalette: (Bool) -> Void
    private let showPalette: (PaletteMode) -> Void
    private let paletteIsVisible: () -> Bool
    private let showSettings: () -> Void
    private let checkForUpdates: () -> Void

    init(
        ranking: LauncherRankingStore,
        appIndex: AppIndex,
        settings: AppSettings,
        palette: PaletteViewModel,
        snippets: SnippetCoordinator,
        quicklinks: QuicklinkCoordinator,
        windowCommands: WindowCommandCoordinator,
        systemCommands: SystemCommandCoordinator,
        hidePalette: @escaping (Bool) -> Void,
        showPalette: @escaping (PaletteMode) -> Void,
        paletteIsVisible: @escaping () -> Bool,
        showSettings: @escaping () -> Void,
        checkForUpdates: @escaping () -> Void
    ) {
        self.ranking = ranking
        self.appIndex = appIndex
        self.settings = settings
        self.palette = palette
        self.snippets = snippets
        self.quicklinks = quicklinks
        self.windowCommands = windowCommands
        self.systemCommands = systemCommands
        self.hidePalette = hidePalette
        self.showPalette = showPalette
        self.paletteIsVisible = paletteIsVisible
        self.showSettings = showSettings
        self.checkForUpdates = checkForUpdates
    }

    func launch(
        _ app: AppEntry,
        searchQuery: String? = nil,
        inlineArgumentValues: [String] = []
    ) {
        ranking.record(itemKey: app.preferenceKey, query: searchQuery ?? "")
        if app.kind == .command {
            runCommand(app, inlineArgumentValues: inlineArgumentValues)
            return
        }
        hidePalette(false)
        switch app.kind {
        case .application:
            Task { [weak self] in
                do {
                    try await AppLauncher.launch(app.url)
                } catch {
                    guard let self else { return }
                    showPalette(.launcher)
                    palette.postFeedback("Could not open \(app.name)", tone: .error)
                }
            }
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command:
            break
        }
    }

    func runHotKey(id: String) {
        guard
            let entry = appIndex.apps.first(where: { $0.id == id })
                ?? CommandRegistry.all.first(where: { $0.id == id })
        else { return }
        if !paletteIsVisible() { showPalette(.launcher) }
        launch(entry)
    }

    func resetRanking(for app: AppEntry) {
        ranking.reset(itemKey: app.preferenceKey)
    }

    func reveal(_ app: AppEntry) {
        hidePalette(false)
        AppLauncher.showInFinder(app.url)
    }

    func copyPath(_ app: AppEntry) {
        hidePalette(false)
        Paster.copyPlainText(app.url.path)
    }

    private func runCommand(_ entry: AppEntry, inlineArgumentValues: [String]) {
        if let command = WindowCommandCatalog.command(forEntryID: entry.id) {
            windowCommands.run(command.id)
            return
        }
        if SystemCommandCatalog.command(forEntryID: entry.id) != nil {
            systemCommands.run(entry)
            return
        }
        switch CommandRegistry.command(for: entry) {
        case .clipboardHistory:
            guard settings.clipboardEnabled else { return }
            palette.enterSubscreen(.clipboard)
        case .searchSnippets:
            snippets.search()
        case .createSnippet:
            snippets.create()
        case .searchQuicklinks:
            quicklinks.search()
        case .createQuicklink:
            quicklinks.create()
        case .searchEmoji:
            guard settings.emojiEnabled else { return }
            palette.enterSubscreen(.emoji)
        case .settings:
            hidePalette(false)
            showSettings()
        case .checkForUpdates:
            checkForUpdates()
        case .quit:
            NSApp.terminate(nil)
        case .caffeinate:
            systemCommands.caffeinate(duration: nil)
        case .decaffeinate:
            systemCommands.decaffeinate()
        case .caffeinateFor:
            guard let duration = systemCommands.duration(from: inlineArgumentValues) else { return }
            systemCommands.caffeinate(duration: duration)
        case nil:
            break
        }
    }
}
