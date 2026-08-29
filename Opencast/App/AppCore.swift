import AppKit
import SwiftUI

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
    lazy var launcher = LauncherCoordinator(
        ranking: launcherRanking,
        appIndex: appIndex,
        settings: settings,
        palette: palette,
        snippets: snippets,
        quicklinks: quicklinks,
        windowCommands: windowCommands,
        systemCommands: systemCommands,
        hidePalette: { [weak self] restoreFocus in self?.hidePalette(restoreFocus: restoreFocus) },
        showPalette: { [weak self] mode in self?.showPalette(mode: mode) },
        paletteIsVisible: { [weak self] in self?.windowController.isVisible ?? false },
        showSettings: { [weak self] in self?.showSettings() },
        checkForUpdates: { [weak self] in self?.checkForUpdates() }
    )
    private let toastWindowController = ToastWindowController()

    private let dialogs = DialogController()
    private let healthTicker = HealthTicker()
    private lazy var windowController = PaletteWindowController(core: self, dialogs: dialogs)

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

    private let auxWindows = AuxWindowController()

    private init() {
        let launcherRanking = LauncherRankingStore()
        self.launcherRanking = launcherRanking
        appIndex = AppIndex(ranking: launcherRanking)
        hotKeys = HotKeyManager(entries: { [weak appIndex] in appIndex?.apps ?? [] })
        clipboardManager = ClipboardManager(store: clipboardStore, settings: settings)
        snippetExpansionMonitor = SnippetExpansionMonitor(store: snippetStore, settings: settings)
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
        hotKeys.onRunCommand = { [weak self] id in self?.launcher.runHotKey(id: id) }
        hotKeys.onRunWindowCommand = { [weak self] id in self?.windowCommands.run(id) }
        hotKeys.allowsAction = { [weak self] action in
            guard let self, self.visibility.allowsHotKey(action) else { return false }
            switch action {
            case .toggleClipboard:
                return self.settings.clipboardEnabled
            case .toggleEmoji:
                return self.settings.emojiEnabled
            case .windowCommand:
                return self.settings.windowManagementEnabled
            default:
                return true
            }
        }
        hotKeys.start()

        // First launch has no palette hotkey bound and shows nothing but the menu-bar icon; guide the user once. Marker is written at show-time so it stays one-time even if they Cmd-Q mid-flow.
        if !OnboardingState.hasOnboarded {
            OnboardingState.markShown()
            showOnboarding()
        }
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
        let preserved = windowController.consumePreservedState()
        if !(preserved && (restoreAnyMode || palette.mode == mode)) {
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
        palette.prepare(mode: .launcher)
    }

    func handlePaletteEscape() {
        if !palette.query.isEmpty {
            palette.query = ""
            palette.selection = 0
            return
        }
        if palette.mode != .launcher {
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

    func closeSettings() {
        auxWindows.close(id: "settings")
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

}
