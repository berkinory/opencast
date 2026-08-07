import AppKit
import SwiftUI

enum PaletteMode: String, CaseIterable, Identifiable {
    case launcher
    case clipboard
    case emoji
    case snippets
    case snippetEditor
    case quicklinks
    case quicklinkEditor
    case uninstall
    case extensionCommand
    case store

    var id: String { rawValue }
    var title: String {
        switch self {
        case .launcher: return "Apps"
        case .clipboard: return "Clipboard History"
        case .emoji: return "Emoji & Symbols"
        case .snippets: return "Snippets"
        case .snippetEditor: return "Snippet"
        case .quicklinks: return "Quicklinks"
        case .quicklinkEditor: return "Quicklink"
        case .uninstall: return "Uninstall"
        case .extensionCommand: return "Extension"
        case .store: return "Store"
        }
    }
    var systemImage: String {
        switch self {
        case .launcher: return "magnifyingglass"
        case .clipboard: return "doc.on.clipboard"
        case .emoji: return "face.smiling"
        case .snippets, .snippetEditor: return "text.quote"
        case .quicklinks, .quicklinkEditor: return "link"
        case .uninstall: return "trash"
        case .extensionCommand: return "puzzlepiece.extension"
        case .store: return "shippingbox.fill"
        }
    }
    var placeholder: String {
        switch self {
        case .launcher: return "Search for apps and commands…"
        case .clipboard: return "Type to filter entries…"
        case .emoji: return "Search emoji and symbols…"
        case .snippets: return "Search snippets…"
        case .snippetEditor: return ""
        case .quicklinks: return "Search quicklinks…"
        case .quicklinkEditor: return ""
        case .uninstall: return "Filter files and folders by name…"
        case .extensionCommand: return "Search extension items…"
        case .store: return "Search extensions…"
        }
    }
}

/// The app a paste will land in, resolved once per palette show so the footer pill and menu rows can name it without re-reading `NSWorkspace` on every render.
struct PaletteFeedback: Equatable, Identifiable {
    enum Tone: Equatable {
        case success
        case warning
        case error
    }

    let id = UUID()
    let message: String
    let tone: Tone
}

struct PasteTarget: Equatable {
    let name: String
    /// Bundle path for `IconCache` — nil for a target with no on-disk bundle.
    let iconPath: String?

    init?(app: NSRunningApplication?) {
        guard let app, let name = app.localizedName else { return nil }
        self.name = name
        iconPath = app.bundleURL?.path
    }

    var pasteTitle: String { "Paste to \(name)" }
}

/// View-model shared between the panel's SwiftUI tree and the coordinator.
enum PaletteRowNavigation {
    case offset(Int)
    case edge(Int)
}

@MainActor
final class PaletteViewModel: ObservableObject {
    @Published var mode: PaletteMode = .launcher
    @Published var query: String = ""
    @Published var selection: Int = 0
    /// Changes every time the palette is shown so the search field can re-focus.
    @Published var focusToken = UUID()
    /// Changes only when `prepare` resets the palette, so the lists snap their scroll to the top even when query/mode were already at their defaults (`focusToken` can't serve: it bumps on every reopen, which must preserve a within-timeout scroll).
    @Published var resetToken = UUID()
    /// Changes when returning to the launcher so the search field can select its restored query.
    @Published var selectQueryToken = UUID()
    @Published var feedback: PaletteFeedback?
    @Published var snippetEditingID: Snippet.ID?
    @Published var snippetEditorReturnsToSearch = false
    @Published var quicklinkEditingID: Quicklink.ID?
    @Published var quicklinkEditorReturnsToSearch = false
    @Published var extensionCommand: ExtensionCommand?
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    @Published var followToken = UUID()
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    @Published var forceExpanded = false
    private var launcherQueryForReturn: String?
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    @Published var pasteTarget: PasteTarget?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Plain, not `@Published` — read at hover time, never drives a re-render.
    var hoverHighlightArmed = false
    /// True while a footer popover menu (⌘K Actions or the app menu) is open, so `PalettePanel.sendEvent` swallows text-editing keystrokes the field editor would otherwise consume — the query must stay frozen while a menu owns the keyboard (matches Raycast). Plain, not `@Published` — read at event time, mirrored from the view's menu state.
    var menuOpen = false { didSet { onMenuOpenChanged?(menuOpen) } }
    /// Fired when `menuOpen` flips so `PalettePanel` can hide/show the search field's caret while it keeps first-responder status (no focus swap, so the placeholder never reflows).
    var onMenuOpenChanged: ((Bool) -> Void)?
    var onCommandEnter: (() -> Bool)?
    var onInlineArgumentsTab: (() -> Bool)?
    var onInlineArgumentsEscape: (() -> Bool)?
    var onInlineArgumentsVerticalArrow: ((Int) -> Bool)?
    var onRowNavigation: ((PaletteRowNavigation) -> Bool)?

    func prepare(mode: PaletteMode) {
        launcherQueryForReturn = nil
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        snippetEditingID = nil
        snippetEditorReturnsToSearch = false
        quicklinkEditingID = nil
        quicklinkEditorReturnsToSearch = false
        extensionCommand = nil
        onCommandEnter = nil
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }

    func enterSubscreen(_ mode: PaletteMode) {
        launcherQueryForReturn = self.mode == .launcher ? query : launcherQueryForReturn
        self.mode = mode
        query = ""
        selection = 0
        forceExpanded = false
        snippetEditingID = nil
        snippetEditorReturnsToSearch = false
        quicklinkEditingID = nil
        quicklinkEditorReturnsToSearch = false
        extensionCommand = nil
        onCommandEnter = nil
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }

    func returnToLauncher() {
        let queryToRestore = launcherQueryForReturn ?? query
        launcherQueryForReturn = nil
        mode = .launcher
        query = queryToRestore
        selection = 0
        forceExpanded = false
        snippetEditingID = nil
        snippetEditorReturnsToSearch = false
        quicklinkEditingID = nil
        quicklinkEditorReturnsToSearch = false
        extensionCommand = nil
        onCommandEnter = nil
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
        selectQueryToken = UUID()
    }

    func enterExtension(_ command: ExtensionCommand) {
        launcherQueryForReturn = self.mode == .launcher ? query : launcherQueryForReturn
        extensionCommand = command
        mode = .extensionCommand
        query = ""
        selection = 0
        forceExpanded = false
        snippetEditingID = nil
        snippetEditorReturnsToSearch = false
        quicklinkEditingID = nil
        quicklinkEditorReturnsToSearch = false
        onCommandEnter = nil
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
    }

    func postFeedback(_ message: String, tone: PaletteFeedback.Tone = .success) {
        feedback = PaletteFeedback(message: message, tone: tone)
    }
}

/// Single owner of every long-lived manager. Wired up once from the app delegate.
@MainActor
final class AppCore: ObservableObject {
    static let shared = AppCore()

    let launcherRanking: LauncherRankingStore
    let appIndex: AppIndex
    let clipboardStore = ClipboardStore()
    let snippetStore = SnippetStore()
    let quicklinkStore = QuicklinkStore()
    let snippetExpansionMonitor: SnippetExpansionMonitor
    let clipboardManager: ClipboardManager
    let hotKeys: HotKeyManager
    let settings = AppSettings()
    let favorites = FavoritesStore()
    let visibility = VisibilityStore()
    let currencyRates = CurrencyRateStore()
    let emojiIndex = EmojiIndex()
    let frequentEmoji = FrequentEmojiStore()
    let runningApps = RunningAppsMonitor()
    let uninstall = UninstallSession()
    let windowMover = WindowMover()
    let updates = UpdateStore()
    let palette = PaletteViewModel()
    let extensionCatalog: ExtensionCatalog
    let extensionStore: ExtensionStoreManager
    lazy var extensionCapabilities = ExtensionCapabilityBroker(
        previousApplication: { [weak self] in self?.windowController.previousApp },
        confirmAction: { [weak self] message, informativeText, confirmTitle in
            self?.confirmExtensionAction(
                message: message,
                informativeText: informativeText,
                confirmTitle: confirmTitle) ?? false
        }
    )
    lazy var extensionHost = ExtensionHostManager(
        capabilityBroker: extensionCapabilities,
        showHUD: { [weak self] message, id, style in
            self?.showHUD(message, id: id, style: style)
        },
        confirmAction: { [weak self] message, informativeText, confirmTitle in
            self?.confirmExtensionAction(
                message: message,
                informativeText: informativeText,
                confirmTitle: confirmTitle) ?? false
        }
    )
    lazy var extensionScheduler = ExtensionScheduler(capabilityBroker: extensionCapabilities)
    lazy var snippets = SnippetCoordinator(
        store: snippetStore,
        settings: settings,
        palette: palette,
        previousApplication: { [weak self] in self?.windowController.previousApp },
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) }
    )
    lazy var quicklinks = QuicklinkCoordinator(
        store: quicklinkStore,
        settings: settings,
        palette: palette,
        favorites: favorites,
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) },
        chooseTarget: { [weak self] completion in
            self?.windowController.presentFilePicker { url in
                guard let url else { return }
                completion(url.path)
            }
        }
    )
    lazy var clipboard = ClipboardCoordinator(
        store: clipboardStore,
        palette: palette,
        previousApplication: { [weak self] in self?.windowController.previousApp },
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) },
        pasteKeepingOpen: { [weak self] item, store in
            self?.windowController.pasteKeepingWindowOpen(item, store: store) ?? false
        },
        confirmDeleteAll: { [weak self] completion in
            self?.windowController.confirmDeleteAllClipboardEntries(onConfirmed: completion)
        }
    )
    lazy var emojis = EmojiCoordinator(
        frequent: frequentEmoji,
        settings: settings,
        previousApplication: { [weak self] in self?.windowController.previousApp },
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) },
        pasteKeepingOpen: { [weak self] text in
            self?.windowController.pasteStringKeepingWindowOpen(text)
        }
    )
    lazy var calculator = CalculatorCoordinator(
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) }
    )
    lazy var windowCommands = WindowCommandCoordinator(
        settings: settings,
        mover: windowMover,
        paletteIsVisible: { [weak self] in self?.windowController.isVisible ?? false },
        previousApplication: { [weak self] in self?.windowController.previousApp },
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) }
    )
    lazy var systemCommands = SystemCommandCoordinator(
        appIndex: appIndex,
        palette: palette,
        dialogs: dialogs,
        previousApplication: { [weak self] in self?.windowController.previousApp },
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) },
        confirm: { [weak self] message, informativeText, confirmTitle in
            self?.windowController.presentConfirmation(
                message: message,
                informativeText: informativeText,
                confirmTitle: confirmTitle) ?? false
        }
    )
    lazy var uninstaller = UninstallCoordinator(
        session: uninstall,
        palette: palette,
        appIndex: appIndex,
        favorites: favorites,
        visibility: visibility,
        ranking: launcherRanking,
        hotKeys: hotKeys,
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) },
        confirm: { [weak self] message, informativeText, confirmTitle in
            self?.windowController.presentConfirmation(
                message: message,
                informativeText: informativeText,
                confirmTitle: confirmTitle) ?? false
        }
    )
    private let toastWindowController = ToastWindowController()

    private let dialogs = DialogController()
    private let healthTicker = HealthTicker()
    private lazy var windowController = PaletteWindowController(core: self, dialogs: dialogs)

    var previousApplicationForExtension: NSRunningApplication? { windowController.previousApp }

    func presentDialog(
        message: String,
        informativeText: String,
        primaryTitle: String,
        secondaryTitle: String? = nil,
        style: NSAlert.Style = .informational,
        primaryIsDestructive: Bool = false
    ) -> NativeConfirmation.Response {
        dialogs.show(
            message: message,
            informativeText: informativeText,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            style: style,
            primaryIsDestructive: primaryIsDestructive
        )
    }

    func confirmExtensionAction(
        message: String, informativeText: String, confirmTitle: String
    ) -> Bool {
        windowController.presentConfirmation(
            message: message,
            informativeText: informativeText,
            confirmTitle: confirmTitle
        )
    }

    private let auxWindows = AuxWindowController()

    private init() {
        let launcherRanking = LauncherRankingStore()
        self.launcherRanking = launcherRanking
        appIndex = AppIndex(ranking: launcherRanking)
        hotKeys = HotKeyManager(entries: { [weak appIndex] in appIndex?.apps ?? [] })
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        snippetExpansionMonitor = SnippetExpansionMonitor(store: snippetStore, settings: settings)
        extensionCatalog = ExtensionCatalog()
        extensionStore = ExtensionStoreManager(directory: extensionCatalog.directory)
        extensionHost.onNoViewFinished = { [weak self] in
            self?.hidePalette()
        }
        extensionStore.onChange = { [weak self] in
            self?.reloadExtensions()
        }
    }

    func start() {
        // AppKit's default tooltip delay is ~2–3s; shorten it (in ms) so the compact-bar favorite tooltips appear promptly. Registration domain — never overrides a user default.
        UserDefaults.standard.register(defaults: ["NSInitialToolTipDelay": 250])
        NSApp.setActivationPolicy(.accessory)
        applyDarkAppearance()

        clipboardStore.maxAge = settings.clipboardRetention.maxAge
        // Defer the initial SQLite read + stale-image prune off the synchronous launch path so the menu bar is interactive immediately; `items` is @Published, so the palette fills in when it lands.
        Task { clipboardStore.load() }
        hotKeys.healthTicker = healthTicker
        snippetExpansionMonitor.healthTicker = healthTicker
        clipboardManager.start()
        snippetExpansionMonitor.start()

        extensionStore.start()
        extensionCatalog.setDisabledNames(extensionStore.disabledNames)
        appIndex.setExtensionCommands(extensionCatalog.commands)
        extensionScheduler.start(commands: extensionCatalog.commands)

        appIndex.start(settings: settings)
        Task {
            appIndex.setCaffeinationActive(await SystemCommandRunner.isCaffeinateRunning())
            await appIndex.refresh()
        }
        Task { await emojiIndex.load() }
        if settings.calculatorEnabled && settings.currencyConversionEnabled {
            currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
        }
        updates.start()

        hotKeys.onTogglePalette = { [weak self] in self?.togglePalette() }
        hotKeys.onToggleClipboard = { [weak self] in self?.toggleClipboard() }
        hotKeys.onToggleEmoji = { [weak self] in self?.toggleEmoji() }
        hotKeys.onRunCommand = { [weak self] id in self?.runHotKeyCommand(id: id) }
        hotKeys.onRunWindowCommand = { [weak self] id in self?.windowCommands.run(id) }
        hotKeys.start()

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !OnboardingState.hasOnboarded {
            OnboardingState.markShown()
            showOnboarding()
        }
    }

    func shutdown() {
        extensionHost.stop()
        extensionScheduler.stop()
    }

    func reloadExtensions() {
        extensionHost.stop()
        extensionCatalog.setDisabledNames(extensionStore.disabledNames)
        appIndex.setExtensionCommands(extensionCatalog.commands)
        extensionScheduler.reload(commands: extensionCatalog.commands)
        Task { await appIndex.refresh() }
    }

    func importExtension() {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.message = "Choose an .ocx extension package"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        extensionStore.install(from: url)
    }

    private func applyDarkAppearance() {
        let appearance = NSAppearance(named: .darkAqua)
        NSApp.appearance = appearance
        for window in NSApp.windows {
            window.appearance = appearance
        }
    }

    // MARK: - Palette control

    func togglePalette() {
        if windowController.isVisible {
            hidePalette()
        } else {
            showPalette(mode: .launcher, restoreAnyMode: true)
        }
    }

    func toggleClipboard() {
        guard settings.clipboardEnabled else { return }
        if windowController.isVisible, palette.mode == .clipboard {
            hidePalette()
        } else {
            showPalette(mode: .clipboard)
        }
    }

    func toggleEmoji() {
        guard settings.emojiEnabled else { return }
        if windowController.isVisible, palette.mode == .emoji {
            hidePalette()
        } else {
            showPalette(mode: .emoji)
        }
    }

    /// Shows the palette, honoring Pop to Root Search: a reopen within the timeout restores the pre-close state — any mode for the generic summon (`restoreAnyMode`), else only when the preserved mode already matches the requested one.
    func showPalette(mode: PaletteMode, restoreAnyMode: Bool = false) {
        if uninstall.target != nil {
            if restoreAnyMode || mode == .uninstall {
                _ = windowController.consumePreservedState()
                palette.mode = .uninstall
                windowController.show()
                return
            }
            uninstall.end()
        }
        let previousMode = palette.mode
        let preserved = windowController.consumePreservedState()
        if !(preserved && (restoreAnyMode || palette.mode == mode)) {
            if previousMode == .extensionCommand { extensionHost.stop() }
            palette.prepare(mode: mode)
        }
        windowController.show()
        // Re-scan on open so an app uninstalled since the last scan drops out of the launcher.
        if palette.mode == .launcher {
            Task {
                appIndex.setCaffeinationActive(await SystemCommandRunner.isCaffeinateRunning())
                await appIndex.refresh()
            }
        }
    }

    func hidePalette(restoreFocus: Bool = true) {
        windowController.hide(restoreFocus: restoreFocus)
    }

    func showHUD(
        _ message: String,
        id: String? = nil,
        style: String? = nil
    ) {
        toastWindowController.show(
            id: id,
            message: message,
            tone: FeedbackToastTone(style: style)
        )
    }

    func hideHUD(id: String? = nil) {
        toastWindowController.hide(id: id)
    }

    func resetPaletteToLauncher() {
        extensionHost.stop()
        palette.prepare(mode: .launcher)
    }

    func handlePaletteEscape() {
        if !palette.query.isEmpty {
            palette.query = ""
            palette.selection = 0
            return
        }
        if palette.mode != .launcher {
            if palette.mode == .extensionCommand {
                extensionHost.stop()
            }
            palette.returnToLauncher()
            return
        }
        hidePalette()
    }

    /// True when the palette should render as the slim compact bar: compact mode on, launcher root, empty query, and not force-expanded via the "…" overflow.
    var paletteIsCollapsed: Bool {
        settings.compactMode
            && !palette.forceExpanded
            && palette.mode == .launcher
            && palette.query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    /// The compact bar's "…" overflow: expand into the full favorites-pinned launcher without typing.
    func expandFromCompact() {
        palette.forceExpanded = true
    }

    /// Resize the panel to match the current collapsed state; called by the view when `paletteIsCollapsed` flips while open.
    func syncPaletteSize() {
        windowController.applyCollapsed(paletteIsCollapsed)
    }

    /// Dock-icon / reopen: focus an open aux window (About/Settings/Onboarding), else summon the launcher. Decoupled from the individual show paths so activation always works.
    func handleReopen() {
        if auxWindows.focusExisting() { return }
        showPalette(mode: .launcher, restoreAnyMode: true)
    }

    /// Settings runs in its own window (the SwiftUI `Settings` scene is unreliable for accessory apps). A fresh window mounts directly on its route; an already-open one navigates in place.
    func showSettings(route: SettingsRoute = .general) {
        let isNew = auxWindows.show(
            id: "settings", title: "Settings", size: Theme.Settings.Size.window,
            seamlessTitleBar: true, transparentBackground: true
        ) {
            SettingsRootView(initialRoute: route)
                .environmentObject(self.appIndex)
                .environmentObject(self.visibility)
        }
        if !isNew {
            NotificationCenter.default.post(name: .opencastSelectSettingsRoute, object: route)
        }
    }

    func showAbout() {
        showSettings(route: .about)
    }

    func checkForUpdates() {
        if updates.isHomebrewManaged {
            checkHomebrewUpdates()
            return
        }
        guard updates.supportsSparkle else {
            palette.postFeedback("Updates are unavailable in development builds", tone: .warning)
            return
        }
        if !updates.networkConsentGranted {
            let response = windowController.presentConfirmationResponse(
                message: "Allow update checks?",
                informativeText:
                    "Opencast will ask Sparkle to check the signed GitHub update feed now. No usage data or system profile is sent.",
                primaryTitle: "Allow",
                secondaryTitle: "Cancel"
            )
            guard response == .primary else { return }
            updates.grantNetworkConsent()
        }
        updates.checkNow()
    }

    private func checkHomebrewUpdates() {
        Task { [weak self] in
            guard let self else { return }
            switch await updates.checkHomebrew() {
            case .upToDate:
                palette.postFeedback("Homebrew reports Opencast is up to date")
            case .updateAvailable(let current, let latest):
                let command = "brew update && brew upgrade --cask opencast"
                if windowController.presentConfirmationResponse(
                    message: "Opencast \(latest) is available",
                    informativeText:
                        "Homebrew manages this installation. Installed: \(current). Run:\n\(command)",
                    primaryTitle: "Copy Command",
                    secondaryTitle: "Later"
                ) == .primary {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(command, forType: .string)
                    palette.postFeedback("Homebrew command copied")
                }
            case .unavailable(let message):
                palette.postFeedback(message, tone: .warning)
            }
        }
    }

    /// The first-run wizard: palette shortcut and Accessibility. Also re-runnable from Settings.
    func showOnboarding() {
        auxWindows.show(
            id: "onboarding", title: "Welcome to Opencast",
            size: OnboardingView.windowSize, seamlessTitleBar: true
        ) {
            OnboardingView()
        }
    }

    /// Final onboarding step: close the wizard and drop straight into the launcher.
    func finishOnboarding() {
        auxWindows.close(id: "onboarding")
        showPalette(mode: .launcher)
    }

    // MARK: - Actions invoked from the palette UI

    func launch(
        _ app: AppEntry,
        searchQuery: String? = nil,
        inlineArgumentValues: [String] = []
    ) {
        // Every palette launch teaches weak global usage; typed launches additionally teach the submitted query and each of its prefixes.
        launcherRanking.record(itemKey: app.preferenceKey, query: searchQuery ?? "")
        // Commands dispatch before the palette hides: mode-switching commands keep it open.
        if let command = extensionCatalog.command(forEntryID: app.id) {
            openExtension(command)
            return
        }
        if app.kind == .command {
            runCommand(app, inlineArgumentValues: inlineArgumentValues)
            return
        }
        hidePalette(restoreFocus: false)
        switch app.kind {
        case .application:
            Task { [weak self] in
                do {
                    try await AppLauncher.launch(app.url)
                } catch {
                    guard let self else { return }
                    showPalette(mode: .launcher)
                    palette.postFeedback("Could not open \(app.name)", tone: .error)
                }
            }
        case .systemSettings:
            guard let bundleID = app.bundleID else { return }
            AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command:
            break  // handled above
        }
    }

    func openExtension(_ command: ExtensionCommand) {
        palette.enterExtension(command)
        extensionHost.start(command)
    }

    func resetRanking(for app: AppEntry) {
        launcherRanking.reset(itemKey: app.preferenceKey)
    }

    private func runCommand(_ entry: AppEntry, inlineArgumentValues: [String] = []) {
        if let command = extensionCatalog.command(forEntryID: entry.id) {
            openExtension(command)
            return
        }
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
        case .store:
            palette.enterSubscreen(.store)
            extensionStore.refreshRemoteCatalog()
        case .importExtension:
            importExtension()
        case .settings:
            hidePalette(restoreFocus: false)
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

    private func runHotKeyCommand(id: String) {
        guard
            let entry = appIndex.apps.first(where: { $0.id == id })
                ?? CommandRegistry.all.first(where: { $0.id == id })
        else { return }
        if !windowController.isVisible { showPalette(mode: .launcher) }
        launch(entry)
    }

    func showInFinder(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        AppLauncher.showInFinder(app.url)
    }

    func copyPath(_ app: AppEntry) {
        hidePalette(restoreFocus: false)
        Paster.copyPlainText(app.url.path)
    }

}
