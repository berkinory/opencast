import AppKit
import SwiftUI

struct ListScrollIntent: Equatable {
    enum Kind: Equatable {
        case follow
        case top
    }

    let id = UUID()
    let kind: Kind
}

struct RootPaletteView: View {
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var vm: PaletteViewModel
    @EnvironmentObject private var appIndex: AppIndex
    @EnvironmentObject private var store: ClipboardStore
    @EnvironmentObject private var snippetStore: SnippetStore
    @EnvironmentObject private var quicklinkStore: QuicklinkStore
    @EnvironmentObject private var favorites: FavoritesStore
    @EnvironmentObject private var visibility: VisibilityStore
    /// Observed so the inline card re-evaluates the moment a fresh FX snapshot lands, or the user
    /// turns currency conversion on or off.
    @EnvironmentObject private var currencyRates: CurrencyRateStore
    @EnvironmentObject private var emojiIndex: EmojiIndex
    @EnvironmentObject private var frequentEmoji: FrequentEmojiStore
    @EnvironmentObject private var uninstall: UninstallSession
    /// Observed so a skin tone changed in Settings re-renders the grid glyphs immediately.
    @ObservedObject private var settings = AppCore.shared.settings
    @FocusState private var searchFocused: Bool
    @State private var showActions = false
    @State private var showAppMenu = false
    @State private var showSortMenu = false
    @State private var clipboardFilter: ClipboardFilter = .all
    /// The selection's running state, sampled once by `openActions` — an app launching or quitting elsewhere must not add or drop the Quit row while the menu is up. `RunningAppsMonitor` is deliberately not observed here: only `LauncherList` needs live running state, and observing it would re-render the whole palette on every workspace launch/terminate.
    @State private var selectionIsRunning = false
    /// Highlighted row of whichever popover menu is open; reset to the first row on open, moved by ↑/↓ and hover, activated by ↵/click.
    @State private var menuSelection = 0
    /// Changes only when a list should follow selection or return to its origin; mouse selection never moves the viewport.
    @State private var listScroll: ListScrollIntent?
    @State private var inlineArgumentValues: [String] = []
    @State private var inlineArgumentFocus: Int?
    @State private var inlineArgumentFocusRequest: Int?

    private var isQueryEmpty: Bool { vm.query.trimmingCharacters(in: .whitespaces).isEmpty }

    /// Slim compact bar vs. full window — the single source of truth lives on `AppCore` so the window controller and this view can never disagree.
    private var isCollapsed: Bool { core.paletteIsCollapsed }

    /// Favorite slots shown in the compact bar: up to 5 launchable apps, or the first 4 plus an overflow "…" that expands the window. Evaluated only in the compact render and on the rare ⌘N keypress.
    private var compactFavoriteSlots: [CompactFavoriteSlot] {
        let favs = appIndex.orderedResults(
            query: "", visibility: visibility, favorites: favorites
        ).prefix(while: favorites.isFavorite)
        if favs.count <= 5 { return favs.map(CompactFavoriteSlot.app) }
        return favs.prefix(4).map(CompactFavoriteSlot.app) + [.more]
    }

    /// Ordered launcher results (the single source of truth for list, selection and activation): empty query pins favorites to the top, otherwise plain ranked matches.
    private var appResults: [AppEntry] {
        appIndex.orderedResults(query: vm.query, visibility: visibility, favorites: favorites)
            .filter { app in
                settings.quicklinksEnabled
                    || ![CommandID.searchQuicklinks.rawValue, CommandID.createQuicklink.rawValue]
                        .contains(app.id)
            }
    }
    private var clipResults: [ClipboardItem] { store.search(vm.query, filter: clipboardFilter) }
    private var snippetResults: [Snippet] { snippetStore.search(vm.query) }
    private var quicklinkResults: [Quicklink] {
        guard settings.quicklinksEnabled else { return [] }
        let results = quicklinkStore.search(vm.query)
        guard isQueryEmpty else { return results }
        let pinned = results.filter(\.isPinned)
        let split = favorites.ordered(results.filter { !$0.isPinned })
        return pinned + split.favorites + split.rest
    }
    private var launcherQuicklinkResults: [Quicklink] {
        vm.mode == .launcher ? quicklinkResults : []
    }
    private var uninstallResults: [LeftoverItem] { uninstall.filtered(vm.query) }
    private var emojiSections: [EmojiGridSection] {
        EmojiGrid.sections(query: vm.query, index: emojiIndex, frequent: frequentEmoji)
    }
    /// Flat grid order across sections — what `vm.selection` indexes in emoji mode.
    private var emojiResults: [EmojiEntry] { emojiSections.flatMap(\.entries) }

    /// Inline calculator answer for the current launcher query; when present it occupies flat selection index 0 so rows shift by `calcCount`.
    private var calcResult: CalcResult? {
        vm.mode == .launcher && settings.calculatorEnabled
            ? CalcMemo.evaluate(
                vm.query,
                currency: settings.currencyConversionEnabled
                    ? currencyRates.source(cryptoEnabled: settings.cryptoConversionEnabled)
                    : .off
            )
            : nil
    }
    private var calcCount: Int { calcResult == nil ? 0 : 1 }

    private var resultCount: Int {
        selectionIndex.count
    }
    /// Selection clamped into the current results — the single source of truth for highlight, preview and activation so the list and preview can never disagree.
    private var selection: Int {
        selectionIndex.clamped(vm.selection)
    }

    private var selectionIndex: PaletteSelectionIndex {
        switch vm.mode {
        case .launcher:
            return PaletteSelectionIndex(
                hasCalculator: calcResult != nil,
                sectionCounts: [appResults.count, launcherQuicklinkResults.count])
        case .clipboard:
            return PaletteSelectionIndex(sectionCounts: [clipResults.count])
        case .emoji:
            return PaletteSelectionIndex(sectionCounts: [emojiResults.count])
        case .snippets:
            return PaletteSelectionIndex(sectionCounts: [snippetResults.count])
        case .quicklinks:
            return PaletteSelectionIndex(sectionCounts: [quicklinkResults.count])
        case .uninstall:
            return PaletteSelectionIndex(
                sectionCounts: [uninstall.phase == .selecting ? uninstallResults.count : 0])
        case .snippetEditor, .quicklinkEditor:
            return PaletteSelectionIndex(sectionCounts: [])
        }
    }

    private var menuOpen: Bool { showActions || showAppMenu || showSortMenu }

    // MARK: - Popover menu content
    //
    // These resolve the current selection for whichever menu is open. They are evaluated only inside the
    // menu overlays (menu visible) or on a keypress (rare), so re-running the unmemoized `appResults`
    // filter here is fine — the same idiom the other rare event handlers use.

    /// The inline calc card sits at flat index 0 when present; only value payloads have a Copy action.
    private var calcActionableResult: CalcResult? {
        guard calcCount > 0, selection == 0, let calc = calcResult, calc.isActionable else {
            return nil
        }
        return calc
    }
    private var selectedAppEntry: AppEntry? {
        let index = selection - calcCount
        return appResults.indices.contains(index) ? appResults[index] : nil
    }
    private var selectedLauncherQuicklink: Quicklink? {
        let index = selection - calcCount - appResults.count
        return launcherQuicklinkResults.indices.contains(index) ? launcherQuicklinkResults[index] : nil
    }
    private var selectedSnippet: Snippet? {
        snippetResults.indices.contains(selection) ? snippetResults[selection] : nil
    }
    private var selectedQuicklink: Quicklink? {
        quicklinkResults.indices.contains(selection) ? quicklinkResults[selection] : nil
    }
    private var gridGeometry: PaletteGridGeometry? {
        switch vm.mode {
        case .emoji:
            return PaletteGridGeometry(
                counts: emojiSections.map(\.entries.count), columns: EmojiGrid.columns)
        default:
            return nil
        }
    }
    private var isGridMode: Bool { gridGeometry != nil }
    private var selectedInlineCommand: CommandID? {
        guard let app = selectedAppEntry else { return nil }
        let command = CommandRegistry.command(for: app)
        return command?.inlineArguments.isEmpty == false ? command : nil
    }
    private var inlineArguments: [InlineArgument] {
        selectedInlineCommand?.inlineArguments ?? []
    }
    private var inlineSearchFieldWidth: CGFloat {
        let font = NSFont.systemFont(
            ofSize: Theme.Size.searchFieldPointSize, weight: .regular)
        return max(
            Theme.Spacing.xs,
            (vm.query as NSString).size(withAttributes: [.font: font]).width
                + Theme.Spacing.xs
        )
    }

    /// The bottom-right Actions menu content for the current mode's selection, or nil when the selection has no actions.
    private var actionsContent: PopoverMenuContent? {
        switch vm.mode {
        case .launcher:
            if let calc = calcActionableResult {
                return CalcActionsMenu.content(result: calc, coordinator: core.calculator)
            }
            if let app = selectedAppEntry {
                return AppActionsMenu.content(
                    app: app, searchQuery: vm.query, core: core, favorites: favorites,
                    running: selectionIsRunning,
                    onResetRanking: {
                        core.launcher.resetRanking(for: app)
                        // Reset can move the item; keep the highlight on the item whose action ran.
                        if let index = appResults.firstIndex(of: app) {
                            vm.selection = index + calcCount
                        }
                    },
                    onToggleFavorite: { toggleFavorite(app) })
            }
            if let quicklink = selectedLauncherQuicklink {
                return QuicklinkActionsMenu.content(
                    quicklink: quicklink, coordinator: core.quicklinks, favorites: favorites,
                    onToggleFavorite: { toggleFavorite(quicklink) },
                    onTogglePinned: { togglePinnedQuicklink(quicklink) })
            }
            return nil
        case .clipboard:
            return clipboardScreen(items: clipResults, selection: selection).actionsContent
        case .emoji:
            return emojiScreen(sections: emojiSections, selection: selection).actionsContent
        case .snippets:
            if let snippet = selectedSnippet {
                return SnippetActionsMenu.content(
                    snippet: snippet, coordinator: core.snippets, target: vm.pasteTarget,
                    onTogglePinned: { togglePinnedSnippet(snippet) })
            }
            return nil
        case .snippetEditor:
            return nil
        case .quicklinks:
            return quicklinkScreen(items: quicklinkResults, selection: selection).actionsContent
        case .quicklinkEditor:
            return nil
        case .uninstall:
            return uninstallScreen(items: uninstallResults, selection: selection).actionsContent
        }
    }

    private var sortMenuContent: PopoverMenuContent {
        UninstallActionsMenu.sortContent(session: uninstall) { sort in
            core.uninstaller.setSort(sort)
            listScroll = ListScrollIntent(kind: .top)
        }
    }

    /// The bottom-left app menu content (About / Settings).
    private var appMenuContent: PopoverMenuContent {
        PopoverMenuContent(items: [
            PopoverMenuItem(title: "About Opencast", systemImage: "info.circle") {
                core.showAbout()
            },
            PopoverMenuItem(title: "Settings", systemImage: "gearshape", shortcut: "⌘,") {
                core.showSettings()
            },
        ])
    }

    /// Whichever menu is open (Actions takes precedence; the two are kept mutually exclusive) — the source for keyboard navigation and activation.
    private var menuContent: PopoverMenuContent? {
        if showActions { return actionsContent }
        if showAppMenu { return appMenuContent }
        if showSortMenu {
            switch vm.mode {
            case .uninstall: return sortMenuContent
            default: return nil
            }
        }
        return nil
    }

    var body: some View {
        // Filter once per render for the active mode only, so the matcher/search doesn't run several times per render (rare event handlers use the computed properties above).
        let apps = vm.mode == .launcher ? appResults : []
        let launcherQuicklinks = vm.mode == .launcher ? launcherQuicklinkResults : []
        let clips = vm.mode == .clipboard ? clipResults : []
        let snippets = vm.mode == .snippets ? snippetResults : []
        let quicklinks = vm.mode == .quicklinks ? quicklinkResults : []
        let emojiSections = vm.mode == .emoji ? emojiSections : []
        let emojis = emojiSections.flatMap(\.entries)
        let uninstallItems = vm.mode == .uninstall ? uninstallResults : []
        // Every count/selection below derives from this one calc/offset pair — the flat selection index must always match the visible row order, calc card included.
        let calc = calcResult
        let offset = calc == nil ? 0 : 1
        // Only the active mode is non-empty.
        let count =
            apps.count + launcherQuicklinks.count + offset + clips.count + snippets.count
            + quicklinks.count
            + emojis.count + uninstallItems.count
        let sel = count == 0 ? 0 : min(max(vm.selection, 0), count - 1)
        let calcSelected = calc != nil && sel == 0
        // An error card is selectable but has no action: it must not drive the Copy Answer pill, ⌘K menu, or Enter.
        let calcActionable = calcSelected && calc?.isActionable == true
        let showSections = vm.mode == .launcher && isQueryEmpty
        let favoriteCount =
            showSections ? apps.prefix(while: { favorites.isFavorite($0) }).count : 0
        let pinnedQuicklinkCount =
            showSections ? launcherQuicklinks.prefix(while: { $0.isPinned }).count : 0
        let favoriteQuicklinkCount =
            showSections
            ? favorites.ordered(launcherQuicklinks.filter { !$0.isPinned }).favorites.count
            : 0
        let selectedApp = apps.indices.contains(sel - offset) ? apps[sel - offset] : nil
        let selectedRootQuicklink =
            launcherQuicklinks.indices.contains(sel - offset - apps.count)
            ? launcherQuicklinks[sel - offset - apps.count]
            : nil
        // Derive the footer label from the already-resolved selection so `bottomBar` doesn't re-run `appResults` (its filter/sort aren't memoized). The primary/Actions group is hidden when there's nothing to act on: no results in any mode, or an error calc card (selectable but action-less).
        let pillLabel = actionPillLabel(
            selectedApp: selectedApp,
            selectedQuicklink: selectedRootQuicklink,
            calcActionable: calcActionable
        )
        let showActionGroup = showsActionGroup(
            count: count, calcBlocked: calcSelected && !calcActionable)

        // The `header` (and its single search field) is always attached in the same position via safeAreaInset so its focus survives the compact↔expanded swap — only the results below it toggle. Collapsed shows the bar alone; expanded floats header + action bar over the list with edge-dissolve (see docs/ui.md).
        return Group {
            if isCollapsed {
                Color.clear
            } else {
                content(
                    apps: apps, launcherQuicklinks: launcherQuicklinks, clips: clips,
                    snippets: snippets, quicklinks: quicklinks,
                    emojiSections: emojiSections, uninstallItems: uninstallItems, calc: calc,
                    selection: sel, favoriteCount: favoriteCount,
                    pinnedQuicklinkCount: pinnedQuicklinkCount,
                    favoriteQuicklinkCount: favoriteQuicklinkCount, showSections: showSections
                )
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) { header }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !isCollapsed, vm.mode != .snippetEditor, vm.mode != .quicklinkEditor {
                bottomBar(pillLabel: pillLabel, showActionGroup: showActionGroup)
            }
        }
        // Menus are in-window overlays anchored to a bottom corner, so they stay clipped inside the panel — never a system popover spilling outside the window.
        .overlay { menuDismissCatcher }
        .overlay(alignment: .bottomLeading) { appMenuOverlay }
        .overlay(alignment: .topTrailing) { sortMenuOverlay }
        .overlay(alignment: .bottomTrailing) { actionsMenuOverlay }
        // The window's own frame (driven by `PaletteWindowController`) is the size source of truth; filling it keeps the glass background and corner clip matched to the current compact/expanded window height.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(Theme.Colors.panelSurface)
        .background(VisualEffectView(material: .hudWindow))
        .overlay {
            RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous)
                .strokeBorder(Theme.Colors.panelStroke, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: Theme.Radius.panel, style: .continuous))
        // Every show bumps focusToken — refocus search and drop any menu left open from last time (e.g. dismissed by clicking away with a context menu up).
        .onChange(of: vm.focusToken) {
            searchFocused = vm.mode != .snippetEditor && vm.mode != .quicklinkEditor
            vm.feedback = nil
            showActions = false
            showAppMenu = false
            showSortMenu = false
        }
        .onChange(of: vm.selectQueryToken) {
            focusAndSelectQuery()
        }
        .onChange(of: vm.query) {
            vm.selection = 0
            inlineArgumentValues.removeAll(keepingCapacity: true)
            inlineArgumentFocus = nil
            inlineArgumentFocusRequest = nil
            listScroll = ListScrollIntent(kind: .top)
        }
        .onChange(of: vm.mode) {
            searchFocused = vm.mode != .snippetEditor && vm.mode != .quicklinkEditor
            vm.selection = 0
            inlineArgumentValues.removeAll(keepingCapacity: true)
            vm.feedback = nil
            showActions = false
            showSortMenu = false
            listScroll = ListScrollIntent(kind: .top)
            if vm.mode != .clipboard { clipboardFilter = .all }
        }
        // Pop-to-root can leave query and mode unchanged, so explicitly restore the content origin.
        .onChange(of: vm.resetToken) {
            listScroll = ListScrollIntent(kind: .top)
        }
        // Opening either menu highlights its first row and closes the other, so exactly one menu is ever open and always has a highlight.
        .onChange(of: menuOpen) { vm.menuOpen = menuOpen }
        .onAppear {
            searchFocused = vm.mode != .snippetEditor && vm.mode != .quicklinkEditor
            vm.onInlineArgumentsTab = handleInlineArgumentTab
            vm.onInlineArgumentsEscape = handleInlineArgumentEscape
            vm.onInlineArgumentsVerticalArrow = handleInlineArgumentVerticalArrow
            vm.onRowNavigation = handleRowNavigation
        }
        .onDisappear {
            vm.onInlineArgumentsTab = nil
            vm.onInlineArgumentsEscape = nil
            vm.onInlineArgumentsVerticalArrow = nil
            vm.onRowNavigation = nil
        }
        .task(id: vm.feedback?.id) {
            guard vm.feedback != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            withAnimation(Self.feedbackAnimation) { vm.feedback = nil }
        }
        // Resize first, then reassert the top after compact mode adopts the full frame.
        .onChange(of: core.paletteIsCollapsed) { oldCollapsed, collapsed in
            core.syncPaletteSize()
            guard oldCollapsed, !collapsed else { return }
            Task { @MainActor in
                await Task.yield()
                guard !core.paletteIsCollapsed else { return }
                listScroll = ListScrollIntent(kind: .top)
            }
        }
        // ⌘1–⌘5 launch the compact bar's favorite slots (or expand, for the "…" overflow slot).
        .onKeyPress(keys: ["1", "2", "3", "4", "5"], phases: .down) { press in
            guard isCollapsed, settings.showFavoritesInCompactMode,
                press.modifiers.contains(.command),
                let digit = press.key.character.wholeNumberValue
            else { return .ignored }
            let slots = compactFavoriteSlots
            let index = digit - 1
            guard slots.indices.contains(index) else { return .ignored }
            switch slots[index] {
            case .app(let app): core.launcher.launch(app)
            case .more: core.expandFromCompact()
            }
            return .handled
        }
        .onKeyPress(.downArrow) {
            if isCollapsed {
                // The compact bar has no visible selection; Down reveals the list at its first row
                // while the shared search field stays mounted and focused.
                vm.selection = 0
                core.expandFromCompact()
                return .handled
            }
            if menuOpen {
                moveMenu(1)
                return .handled
            }
            if isGridMode { moveGridRow(1) } else { move(1) }
            return .handled
        }
        .onKeyPress(.upArrow) {
            if isCollapsed { return .ignored }
            if menuOpen {
                moveMenu(-1)
                return .handled
            }
            if isGridMode { moveGridRow(-1) } else { move(-1) }
            return .handled
        }
        // Horizontal arrows step grid screens; everywhere else they stay with the field editor's caret. An open menu swallows them so the list behind never moves.
        .onKeyPress(.leftArrow) {
            if menuOpen { return .handled }
            guard isGridMode else { return .ignored }
            move(-1)
            return .handled
        }
        .onKeyPress(.rightArrow) {
            if menuOpen { return .handled }
            guard isGridMode else { return .ignored }
            move(1)
            return .handled
        }
        // With a menu open, plain ↵ activates its highlighted row. A modified ↵ always runs the selection's own action regardless of menu state: ⌘↵ the secondary copy action (each menu advertises it), ⌥↵ paste-in-place; plain ↵ (no menu) falls through to the field's onSubmit.
        .onKeyPress(keys: [.return], phases: .down) { press in
            handleModifiedReturn(press) ? .handled : .ignored
        }
        // ⌘F toggles the selected launcher's favorite state while its Actions menu is open.
        .onKeyPress(keys: ["f"], phases: .down) { press in
            guard showActions else { return .ignored }
            guard press.modifiers.contains(.command),
                press.modifiers.intersection([.shift, .option, .control]).isEmpty
            else { return .ignored }
            if vm.mode == .launcher, let app = selectedAppEntry {
                toggleFavorite(app)
            } else if vm.mode == .launcher, let quicklink = selectedLauncherQuicklink {
                toggleFavorite(quicklink)
            } else if vm.mode == .quicklinks, let quicklink = selectedQuicklink {
                toggleFavorite(quicklink)
            } else {
                return .ignored
            }
            closeMenus()
            return .handled
        }
        .onKeyPress(keys: ["c"], phases: .down) { press in
            guard showActions else { return .ignored }
            guard vm.mode == .launcher else { return .ignored }
            guard press.modifiers.contains([.command, .shift]) else { return .ignored }
            guard press.modifiers.intersection([.option, .control]).isEmpty else {
                return .ignored
            }
            guard let app = selectedAppEntry, app.kind == .application else {
                return .ignored
            }
            core.launcher.copyPath(app)
            closeMenus()
            return .handled
        }
        .onKeyPress(.escape) {
            if menuOpen {
                closeMenus()
                return .handled
            }
            handlePaletteEscape()
            return .handled
        }
        .onKeyPress(.tab) {
            if menuOpen { return .handled }
            if vm.mode == .uninstall { return .handled }
            toggleMode()
            return .handled
        }
        // ⌘K toggles the actions panel for the current selection.
        .onKeyPress(keys: ["k"], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            // The Actions menu has no anchor in the compact bar (no bottom bar); swallow ⌘K there.
            guard !isCollapsed else { return .handled }
            guard resultCount > 0 else { return .handled }
            // An error calc card is the selection but has no actions — don't open an empty panel.
            if calcCount > 0 {
                if selection == 0, calcResult?.isActionable != true { return .handled }
            }
            toggleActions()
            return .handled
        }
        // Bare backspace (back out of a sub-screen when the search is empty) is intercepted by PalettePanel.sendEvent — the field editor consumes it before onKeyPress could fire.
        .onKeyPress(keys: [.delete, .deleteForward], phases: .down) { press in
            if menuOpen { return .handled }
            if press.modifiers.contains(.control) {
                if !isCollapsed, vm.mode == .launcher,
                    let app = selectedAppEntry,
                    AppLeftovers.canUninstall(url: app.url, bundleID: app.bundleID)
                {
                    core.uninstaller.begin(app)
                    return .handled
                }
            }
            guard press.modifiers.contains(.command) else { return .ignored }
            if press.modifiers.contains(.shift) {
                if vm.mode == .uninstall, uninstall.phase == .selecting {
                    core.uninstaller.remove(permanently: true)
                    return .handled
                }
            }
            switch vm.mode {
            case .clipboard:
                _ = clipboardScreen(items: clipResults, selection: selection).delete()
            case .launcher, .emoji, .snippets, .snippetEditor, .quicklinks, .quicklinkEditor, .uninstall:
                return .ignored
            }
            return .handled
        }
        // ⌘P pins/unpins the selected item in pin-capable lists, including while Actions is open.
        .onKeyPress(keys: ["p"], phases: .down) { press in
            guard press.modifiers.intersection([.command, .option, .control, .shift]) == .command
            else { return .ignored }
            switch vm.mode {
            case .clipboard:
                guard clipboardScreen(items: clipResults, selection: selection).togglePinned()
                else { return .ignored }
            case .snippets:
                guard snippetResults.indices.contains(selection) else { return .ignored }
                togglePinnedSnippet(snippetResults[selection])
            case .quicklinks:
                guard quicklinkResults.indices.contains(selection) else { return .ignored }
                togglePinnedQuicklink(quicklinkResults[selection])
            case .launcher:
                guard let quicklink = selectedLauncherQuicklink else { return .ignored }
                togglePinnedQuicklink(quicklink)
            default:
                return .ignored
            }
            return .handled
        }
    }

    @ViewBuilder
    private var menuDismissCatcher: some View {
        if menuOpen {
            Theme.Colors.invisibleOverlay
                .contentShape(Rectangle())
                .onTapGesture(perform: closeMenus)
        }
    }

    @ViewBuilder
    private var appMenuOverlay: some View {
        if showAppMenu {
            let content = appMenuContent
            PopoverMenu(
                header: content.header, items: content.items, selection: $menuSelection,
                onActivate: activateMenuItem
            )
            .padding(Self.menuInset)
            .transition(Self.menuTransition(.bottomLeading))
        }
    }

    @ViewBuilder
    private var sortMenuOverlay: some View {
        if showSortMenu,
            let content = sortMenuOverlayContent
        {
            PopoverMenu(
                header: content.header, items: content.items, selection: $menuSelection,
                onActivate: activateMenuItem
            )
            .padding(Self.menuInset)
            .padding(.top, Theme.Size.headerHeight + Theme.Size.headerPadding)
            .transition(Self.menuTransition(.topTrailing))
        }
    }

    private var sortMenuOverlayContent: PopoverMenuContent? {
        switch vm.mode {
        case .uninstall: return sortMenuContent
        default: return nil
        }
    }

    @ViewBuilder
    private var actionsMenuOverlay: some View {
        if showActions, let content = actionsContent {
            PopoverMenu(
                header: content.header, items: content.items, selection: $menuSelection,
                onActivate: activateMenuItem
            )
            .padding(Self.menuInset)
            .transition(Self.menuTransition(.bottomTrailing))
        }
    }

    private var header: some View {
        HStack(alignment: .center, spacing: Theme.Spacing.md) {
            if vm.mode == .launcher {
                Image(systemName: vm.mode.systemImage)
                    .font(Theme.Typography.headerIcon)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(.secondary)
                    .frame(width: Theme.Size.headerIconSlot)
            } else {
                Button(action: exitToLauncher) {
                    Image(systemName: "chevron.left")
                        .font(Theme.Typography.headerIcon)
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                        .frame(width: Theme.Size.headerIconSlot)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .onHover { hovering in
                    if hovering { NSCursor.arrow.set() }
                }
            }

            if vm.mode == .snippetEditor || vm.mode == .quicklinkEditor {
                Spacer(minLength: 0)
                Text(vm.mode == .snippetEditor ? "Snippets Guide" : "Quicklinks Guide")
                    .font(Theme.Typography.callout)
                    .underline()
                    .foregroundStyle(.secondary)
            } else {
                searchField
                    .frame(
                        width: inlineArguments.isEmpty ? nil : inlineSearchFieldWidth,
                        alignment: .leading
                    )
                if !inlineArguments.isEmpty {
                    PaletteInlineArguments(
                        arguments: inlineArguments,
                        values: $inlineArgumentValues,
                        focusRequest: inlineArgumentFocusRequest,
                        onFocusChanged: { inlineArgumentFocus = $0 },
                        onSubmit: activateSelection
                    )
                    Spacer(minLength: 0)
                }
                headerTrailing
            }
        }
        .padding(.horizontal, Theme.Spacing.md * 2)
        .frame(height: Theme.Size.headerHeight)
        .padding(.top, Theme.Size.headerPadding)
        .frame(maxWidth: .infinity)
    }

    @ViewBuilder
    private var headerTrailing: some View {
        if vm.mode == .uninstall, uninstall.phase == .selecting, !uninstall.items.isEmpty {
            UninstallSortButton(sort: uninstall.sort, action: toggleSortMenu)
        }
        if isCollapsed, settings.showFavoritesInCompactMode {
            let slots = compactFavoriteSlots
            if !slots.isEmpty {
                CompactFavoritesRow(
                    slots: slots,
                    onLaunch: { core.launcher.launch($0) },
                    onOverflow: { core.expandFromCompact() }
                )
            }
        }
    }

    /// The one search field, kept in a single tree position (the `header`) so its focus survives the compact↔expanded swap.
    private var searchField: some View {
        TextField(
            "", text: $vm.query,
            prompt: Text(vm.mode.placeholder)
                .foregroundStyle(Theme.Colors.searchPlaceholder)
        )
        .textFieldStyle(.plain)
        .font(Theme.Typography.searchField)
        .tint(Theme.Colors.textPrimary)
        .onGeometryChange(for: CGRect.self) {
            $0.frame(in: .global)
        } action: { frame in
            vm.searchFieldFrame = frame
        }
        .focused($searchFocused)
        .onSubmit(activateSelection)
    }

    private func clipboardScreen(
        items: [ClipboardItem], selection: Int
    ) -> ClipboardPaletteScreen {
        ClipboardPaletteScreen(
            items: items,
            selection: selection,
            scrollIntent: listScroll,
            store: store,
            coordinator: core.clipboard,
            filter: clipboardFilter,
            pasteTarget: vm.pasteTarget,
            followKey: ClipFollowKey(id: store.items.first?.id, token: vm.followToken),
            isQueryEmpty: isQueryEmpty,
            onSelect: { vm.selection = $0 },
            onFollow: { index in
                if let index { vm.selection = index }
                listScroll = ListScrollIntent(kind: .follow)
            },
            onOpenActions: openActions,
            onFeedback: { showFeedback($0) },
            onFilterChange: { filter in
                clipboardFilter = filter
                vm.selection = 0
                listScroll = ListScrollIntent(kind: .top)
            }
        )
    }

    private func quicklinkScreen(
        items: [Quicklink], selection: Int
    ) -> QuicklinkPaletteScreen {
        QuicklinkPaletteScreen(
            items: items,
            selection: selection,
            scrollIntent: listScroll,
            coordinator: core.quicklinks,
            favorites: favorites,
            onSelect: { vm.selection = $0 },
            onOpenActions: openActions,
            onToggleFavorite: toggleFavorite,
            onTogglePinned: togglePinnedQuicklink
        )
    }

    private func emojiScreen(
        sections: [EmojiGridSection], selection: Int
    ) -> EmojiPaletteScreen {
        EmojiPaletteScreen(
            sections: sections,
            selection: selection,
            tone: settings.emojiSkinTone,
            scroll: listScroll ?? ListScrollIntent(kind: .top),
            isLoaded: emojiIndex.isLoaded,
            coordinator: core.emojis,
            pasteTarget: vm.pasteTarget,
            onSelect: { vm.selection = $0 },
            onOpenActions: openActions
        )
    }

    private func uninstallScreen(
        items: [LeftoverItem], selection: Int
    ) -> UninstallPaletteScreen {
        UninstallPaletteScreen(
            items: items,
            selection: selection,
            scrollIntent: listScroll,
            session: uninstall,
            coordinator: core.uninstaller,
            onSelect: { vm.selection = $0 },
            onOpenActions: openActions
        )
    }

    @ViewBuilder
    private func content(
        apps: [AppEntry], launcherQuicklinks: [Quicklink], clips: [ClipboardItem],
        snippets: [Snippet], quicklinks: [Quicklink],
        emojiSections: [EmojiGridSection], uninstallItems: [LeftoverItem], calc: CalcResult?,
        selection: Int, favoriteCount: Int, pinnedQuicklinkCount: Int,
        favoriteQuicklinkCount: Int, showSections: Bool
    ) -> some View {
        switch vm.mode {
        case .launcher:
            let offset = calc == nil ? 0 : 1
            let calcSelected = calc != nil && selection == 0
            let appIndex = selection - offset
            let selectedID = apps.indices.contains(appIndex) ? apps[appIndex].id : nil
            LauncherList(
                results: apps,
                quicklinks: launcherQuicklinks,
                selectedID: calcSelected ? nil : selectedID,
                selectedQuicklinkID: calcSelected
                    ? nil
                    : launcherQuicklinks.indices.contains(selection - offset - apps.count)
                        ? launcherQuicklinks[selection - offset - apps.count].id
                        : nil,
                favoriteCount: favoriteCount,
                pinnedQuicklinkCount: pinnedQuicklinkCount,
                favoriteQuicklinkCount: favoriteQuicklinkCount,
                showSections: showSections,
                scrollIntent: listScroll,
                calc: calc,
                calcSelected: calcSelected,
                onActivateCalc: {
                    vm.selection = 0
                    activateSelection()
                },
                onCalcActions: {
                    guard let calc, case .value = calc.payload else { return }
                    vm.selection = 0
                    openActions()
                },
                onActivate: { activateLauncherApp($0, in: apps, offset: offset) },
                onActions: { app in
                    if let index = apps.firstIndex(of: app) { vm.selection = index + offset }
                    openActions()
                },
                onActivateQuicklink: { quicklink in
                    if let index = launcherQuicklinks.firstIndex(of: quicklink) {
                        vm.selection = index + offset + apps.count
                    }
                    activateSelection()
                },
                onActionsQuicklink: { quicklink in
                    if let index = launcherQuicklinks.firstIndex(of: quicklink) {
                        vm.selection = index + offset + apps.count
                    }
                    openActions()
                }
            )
        case .clipboard:
            clipboardScreen(items: clips, selection: selection)
        case .snippets:
            SnippetSearchView(
                results: snippets,
                selectedID: selectedSnippet?.id,
                scrollIntent: listScroll,
                onSelect: { snippet in vm.selection = snippets.firstIndex(of: snippet) ?? 0 },
                onActivate: { snippet in
                    if let index = snippets.firstIndex(of: snippet) { vm.selection = index }
                    activateSelection()
                },
                onActions: { snippet in
                    if let index = snippets.firstIndex(of: snippet) { vm.selection = index }
                    openActions()
                }
            )
        case .snippetEditor:
            SnippetEditorView(
                snippet: snippetStore.snippet(for: vm.snippetEditingID),
                onSave: saveSnippet
            )
        case .quicklinks:
            quicklinkScreen(items: quicklinks, selection: selection)
        case .quicklinkEditor:
            QuicklinkEditorView(
                quicklink: quicklinkStore.quicklink(for: vm.quicklinkEditingID),
                onSave: saveQuicklink
            )
        case .emoji:
            emojiScreen(sections: emojiSections, selection: selection)
        case .uninstall:
            uninstallScreen(items: uninstallItems, selection: selection)
        }
    }

    private func bottomBar(pillLabel: String, showActionGroup: Bool) -> some View {
        // No bar — just floating glass controls over the list; the edge dissolve ghosts rows passing beneath, so the buttons read clearly without a hard-edged strip.
        HStack(spacing: 0) {
            if vm.mode == .uninstall, let target = uninstall.target {
                UninstallContextPill(
                    name: target.name,
                    icon: IconCache.cached(forFile: target.url.path)
                )
            } else {
                footerMenuButton
            }
            Spacer()
            if showActionGroup {
                actionGroup(
                    pillLabel: pillLabel,
                    destructive: vm.mode == .uninstall && uninstall.phase == .selecting,
                    showActionsToggle:
                        resultCount > 0
                        && (vm.mode != .uninstall || uninstall.phase == .selecting)
                )
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.bottomBarHeight)
        .frame(maxWidth: .infinity)
        .animation(Self.feedbackAnimation, value: vm.feedback?.id)
    }

    @ViewBuilder
    private var footerMenuButton: some View {
        if let feedback = vm.feedback {
            PaletteFeedbackButton(message: feedback.message, tone: feedback.tone)
        } else if vm.mode == .launcher {
            MenuCircleButton(action: toggleAppMenu)
        } else {
            PaletteModeMenuButton(
                mode: vm.mode,
                title: nil,
                action: toggleAppMenu
            )
        }
    }

    /// The footer control group: primary action and the Actions toggle sharing one glass capsule.
    private func actionGroup(
        pillLabel: String, destructive: Bool = false, showActionsToggle: Bool = true
    ) -> some View {
        PaletteActionGroup(
            primaryTitle: pillLabel,
            primaryShortcut: ["↵"],
            primaryAction: { activateSelection() },
            primaryColor: destructive ? .red : Theme.Colors.textPrimary,
            secondaryTitle: showActionsToggle ? "Actions" : nil,
            secondaryShortcut: ["⌘", "K"],
            secondaryAction: showActionsToggle ? { toggleActions() } : nil
        )
    }

    /// Pill label for the current selection, derived from the selection already resolved in `body` so it never re-runs the (unmemoized) `appResults` filter/sort.
    private func actionPillLabel(
        selectedApp: AppEntry?, selectedQuicklink: Quicklink?, calcActionable: Bool
    ) -> String {
        switch vm.mode {
        case .clipboard, .emoji:
            return vm.pasteTarget?.pasteTitle ?? "Paste"
        case .snippets:
            return snippetResults.isEmpty ? "Create Snippet" : vm.pasteTarget?.pasteTitle ?? "Paste"
        case .snippetEditor:
            return "Save Snippet"
        case .quicklinks:
            return quicklinkResults.isEmpty ? "Create Quicklink" : "Open Quicklink"
        case .quicklinkEditor:
            return "Save Quicklink"
        case .launcher:
            if calcActionable { return "Copy Answer" }
            if selectedQuicklink != nil { return "Open Quicklink" }
            return selectedApp?.primaryActionTitle ?? "Open Application"
        case .uninstall:
            switch uninstall.phase {
            case .selecting:
                return uninstall.checkedItems.isEmpty ? "Nothing Checked" : "Uninstall Application"
            case .removing: return "Removing…"
            case .done: return "Back to Search"
            }
        }
    }

    private func showsActionGroup(count: Int, calcBlocked: Bool) -> Bool {
        if vm.mode == .uninstall {
            switch uninstall.phase {
            case .selecting: return count > 0
            case .removing: return false
            case .done: return true
            }
        }
        if vm.mode == .snippets, snippetResults.isEmpty { return true }
        if vm.mode == .quicklinks, quicklinkResults.isEmpty { return true }
        return count > 0 && !calcBlocked
    }

    private func toggleFavorite(_ app: AppEntry) {
        let added = !favorites.isFavorite(app)
        favorites.toggle(app)
        showFeedback(added ? "Added to favorites" : "Removed from favorites")
    }

    private func toggleFavorite(_ quicklink: Quicklink) {
        let added = !favorites.isFavorite(quicklink)
        favorites.toggle(quicklink)
        showFeedback(added ? "Added to favorites" : "Removed from favorites")
    }

    private func togglePinnedSnippet(_ snippet: Snippet) {
        core.snippets.togglePinned(snippet)
        if let index = snippetResults.firstIndex(where: { $0.id == snippet.id }) {
            vm.selection = index
        }
        listScroll = ListScrollIntent(kind: .follow)
    }

    private func togglePinnedQuicklink(_ quicklink: Quicklink) {
        core.quicklinks.togglePinned(quicklink)
        if vm.mode == .launcher {
            if let index = launcherQuicklinkResults.firstIndex(where: { $0.id == quicklink.id }) {
                vm.selection = calcCount + appResults.count + index
            }
        } else if let index = quicklinkResults.firstIndex(where: { $0.id == quicklink.id }) {
            vm.selection = index
        }
        listScroll = ListScrollIntent(kind: .follow)
    }

    private func showFeedback(
        _ message: String, tone: PaletteFeedback.Tone = .success
    ) {
        withAnimation(Self.feedbackAnimation) {
            vm.postFeedback(message, tone: tone)
        }
    }

    /// The single path that opens the Actions menu: samples the state its rows depend on, then shows it. Callers set `vm.selection` first, so the sample matches the row the menu is for.
    private func openActions() {
        // Only the launcher's menu carries a Quit row, so the other modes skip the (unmemoized) `appResults` walk entirely.
        if vm.mode == .launcher, let app = selectedAppEntry {
            selectionIsRunning = core.runningApps.isRunning(app)
        } else {
            selectionIsRunning = false
        }
        guard actionsContent != nil else { return }
        withAnimation(Self.menuAnimation) {
            showAppMenu = false
            showSortMenu = false
            menuSelection = 0
            showActions = true
        }
    }

    private func toggleActions() {
        if showActions {
            withAnimation(Self.menuAnimation) { showActions = false }
        } else {
            openActions()
        }
    }

    private func toggleAppMenu() {
        withAnimation(Self.menuAnimation) {
            let opening = !showAppMenu
            showActions = false
            showSortMenu = false
            menuSelection = 0
            showAppMenu = opening
        }
    }

    private func toggleSortMenu() {
        withAnimation(Self.menuAnimation) {
            let opening = !showSortMenu
            showActions = false
            showAppMenu = false
            menuSelection = 0
            showSortMenu = opening
        }
    }

    private func closeMenus() {
        withAnimation(Self.menuAnimation) {
            showActions = false
            showAppMenu = false
            showSortMenu = false
        }
    }

    /// Inset of the menu panels from the window's bottom corners, kept just inside the rounded corner so the menu's own corner isn't clipped.
    private static let menuInset: CGFloat = 8
    private static let menuAnimation: Animation = .easeOut(duration: 0.14)
    private static let feedbackAnimation: Animation = .easeOut(duration: 0.14)

    private static func menuTransition(_ anchor: UnitPoint) -> AnyTransition {
        .opacity.combined(with: .scale(scale: 0.96, anchor: anchor))
    }

    // MARK: - Actions

    private func handleModifiedReturn(_ press: KeyPress) -> Bool {
        let command = press.modifiers.contains(.command)
        let option = press.modifiers.contains(.option)
        if menuOpen, !command, !option {
            activateMenuItem(menuSelection)
            return true
        }
        guard command || option else { return false }
        switch vm.mode {
        case .emoji:
            let screen = emojiScreen(sections: emojiSections, selection: selection)
            return command ? screen.copy() : screen.pasteKeepingOpen()
        case .clipboard:
            guard command else { return false }
            return clipboardScreen(items: clipResults, selection: selection).copy()
        case .snippets:
            guard command, snippetResults.indices.contains(selection) else { return false }
            core.snippets.copy(snippetResults[selection])
        case .quicklinks:
            guard command else { return false }
            return quicklinkScreen(items: quicklinkResults, selection: selection).copy()
        case .snippetEditor, .quicklinkEditor:
            return false
        case .launcher:
            guard command, let app = selectedAppEntry else { return false }
            let canShowInFinder = app.kind == .application || app.kind == .systemSettings
            guard canShowInFinder else { return false }
            core.launcher.reveal(app)
        case .uninstall:
            guard command else { return false }
            return uninstallScreen(items: uninstallResults, selection: selection).reveal()
        }
        return true
    }

    private func handlePaletteEscape() {
        switch vm.mode {
        case .uninstall:
            core.uninstaller.exit()
        case .snippetEditor:
            core.snippets.exitEditor()
        default:
            core.handlePaletteEscape()
        }
    }

    private func handleInlineArgumentTab() -> Bool {
        guard !inlineArguments.isEmpty else { return false }
        if let focused = inlineArgumentFocus ?? inlineArgumentFocusRequest {
            if inlineArguments.indices.contains(focused + 1) {
                inlineArgumentFocusRequest = focused + 1
            } else {
                leaveInlineArguments()
            }
        } else {
            searchFocused = false
            inlineArgumentFocusRequest = inlineArguments.startIndex
        }
        return true
    }

    private func handleInlineArgumentEscape() -> Bool {
        guard (inlineArgumentFocus ?? inlineArgumentFocusRequest) != nil else { return false }
        leaveInlineArguments()
        return true
    }

    private func handleInlineArgumentVerticalArrow(_ delta: Int) -> Bool {
        guard vm.mode == .launcher, !isCollapsed else { return false }
        if menuOpen {
            moveMenu(delta)
        } else {
            move(delta)
        }
        return true
    }

    private func handleRowNavigation(_ navigation: PaletteRowNavigation) -> Bool {
        guard !isCollapsed else { return false }
        guard menuOpen || resultCount > 0 else { return false }
        switch navigation {
        case .offset(let delta):
            if menuOpen {
                moveMenu(delta)
            } else if isGridMode {
                moveGridRows(delta)
            } else {
                move(delta)
            }
        case .edge(let direction):
            if menuOpen {
                moveMenuToEdge(direction)
            } else if isGridMode {
                moveGridToEdge(direction)
            } else {
                moveToEdge(direction)
            }
        }
        return true
    }

    private func leaveInlineArguments() {
        inlineArgumentFocusRequest = nil
        inlineArgumentFocus = nil
        focusAndSelectQuery()
    }

    private func move(_ delta: Int) {
        guard resultCount > 0 else { return }
        let nextSelection = min(max(selection + delta, 0), resultCount - 1)
        if nextSelection != selection {
            inlineArgumentFocus = nil
            inlineArgumentFocusRequest = nil
            searchFocused = true
        }
        vm.selection = nextSelection
        let kind: ListScrollIntent.Kind = delta < 0 && nextSelection == 0 ? .top : .follow
        listScroll = ListScrollIntent(kind: kind)
    }

    private func moveToEdge(_ direction: Int) {
        guard resultCount > 0 else { return }
        move((direction < 0 ? 0 : resultCount - 1) - selection)
    }

    /// Move the open menu's highlight, clamped at the ends (no wrap — consistent with `move`).
    private func moveMenu(_ delta: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = min(max(menuSelection + delta, 0), count - 1)
    }

    private func moveMenuToEdge(_ direction: Int) {
        guard let count = menuContent?.items.count, count > 0 else { return }
        menuSelection = direction < 0 ? 0 : count - 1
    }

    /// The single activation path for a menu row, shared by a click and Return: run the row's action, then close.
    private func activateMenuItem(_ index: Int) {
        guard let items = menuContent?.items, items.indices.contains(index) else { return }
        items[index].action()
        closeMenus()
    }

    private func moveGridRow(_ delta: Int) {
        guard let gridGeometry else { return }
        let nextSelection =
            delta > 0
            ? gridGeometry.down(from: selection)
            : gridGeometry.up(from: selection)
        vm.selection = nextSelection
        listScroll = ListScrollIntent(kind: .follow)
    }

    private func moveGridRows(_ delta: Int) {
        let steps = abs(delta)
        guard steps > 0 else { return }
        for _ in 0..<steps {
            let previous = selection
            moveGridRow(delta > 0 ? 1 : -1)
            if selection == previous { break }
        }
    }

    private func moveGridToEdge(_ direction: Int) {
        guard resultCount > 0 else { return }
        vm.selection = direction < 0 ? 0 : resultCount - 1
        listScroll = ListScrollIntent(kind: .follow)
    }

    /// Tab flips between the launcher and clipboard.
    private func toggleMode() {
        guard vm.mode == .launcher || vm.mode == .clipboard else { return }
        guard settings.clipboardEnabled else { return }
        vm.mode = vm.mode == .launcher ? .clipboard : .launcher
    }

    /// Return to the launcher and restore the query that opened the sub-screen.
    private func exitToLauncher() {
        if vm.mode == .uninstall {
            core.uninstaller.exit()
            return
        }
        if vm.mode == .snippetEditor {
            core.snippets.exitEditor()
            return
        }
        if vm.mode == .quicklinkEditor {
            core.quicklinks.exitEditor()
            return
        }
        vm.returnToLauncher()
    }

    private func saveSnippet(_ draft: SnippetDraft) -> String? {
        do {
            let isEditing = vm.snippetEditingID != nil
            if let current = snippetStore.snippet(for: vm.snippetEditingID) {
                _ = try snippetStore.update(
                    Snippet(
                        id: current.id, name: draft.name, content: draft.content,
                        keyword: draft.keyword, icon: draft.icon, createdAt: current.createdAt,
                        pinnedAt: current.pinnedAt
                    )
                )
            } else {
                _ = try snippetStore.create(
                    name: draft.name, content: draft.content,
                    keyword: draft.keyword, icon: draft.icon
                )
            }
            if isEditing {
                vm.mode = .snippets
                vm.query = ""
                vm.selection = 0
                vm.snippetEditingID = nil
                vm.snippetEditorReturnsToSearch = false
                vm.focusToken = UUID()
                vm.resetToken = UUID()
            } else {
                core.snippets.exitEditor()
                Task { @MainActor in
                    await Task.yield()
                    vm.postFeedback("Created snippet")
                }
            }
            return nil
        } catch let error as SnippetValidationError {
            return error.localizedDescription
        } catch {
            return "Could not save snippet"
        }
    }

    private func saveQuicklink(_ draft: QuicklinkDraft) -> String? {
        do {
            let isEditing = vm.quicklinkEditingID != nil
            if let current = quicklinkStore.quicklink(for: vm.quicklinkEditingID) {
                _ = try quicklinkStore.update(
                    Quicklink(
                        id: current.id,
                        name: draft.name,
                        link: draft.link,
                        icon: draft.icon,
                        openWithBundleID: draft.openWithBundleID,
                        createdAt: current.createdAt,
                        pinnedAt: current.pinnedAt
                    )
                )
            } else {
                _ = try quicklinkStore.create(
                    name: draft.name,
                    link: draft.link,
                    icon: draft.icon,
                    openWithBundleID: draft.openWithBundleID
                )
            }
            if isEditing {
                vm.mode = .quicklinks
                vm.query = ""
                vm.selection = 0
                vm.quicklinkEditingID = nil
                vm.quicklinkEditorReturnsToSearch = false
                vm.focusToken = UUID()
                vm.resetToken = UUID()
            } else {
                core.quicklinks.exitEditor()
                Task { @MainActor in
                    await Task.yield()
                    vm.postFeedback("Created quicklink")
                }
            }
            return nil
        } catch let error as QuicklinkValidationError {
            return error.localizedDescription
        } catch {
            return "Could not save quicklink"
        }
    }

    private func focusAndSelectQuery() {
        searchFocused = false
        DispatchQueue.main.async {
            searchFocused = true
            DispatchQueue.main.async {
                guard let editor = NSApp.keyWindow?.firstResponder as? NSTextView else { return }
                editor.selectAll(nil)
            }
        }
    }

    private func activateSelection() {
        // Nothing is visibly selected in the collapsed compact bar; launch only via ⌘1–⌘5 or by typing.
        guard !isCollapsed else { return }
        switch vm.mode {
        case .launcher:
            if let calcResult, selection == 0 {
                // Error cards no-op — copyCalculatorResult only acts on value payloads.
                core.calculator.copy(calcResult)
                return
            }
            let index = selection - calcCount
            if appResults.indices.contains(index) {
                launchApp(appResults[index])
                return
            }
            let quicklinkIndex = index - appResults.count
            guard launcherQuicklinkResults.indices.contains(quicklinkIndex) else { return }
            core.quicklinks.open(launcherQuicklinkResults[quicklinkIndex])
        case .clipboard:
            clipboardScreen(items: clipResults, selection: selection).activate()
        case .snippets:
            guard snippetResults.indices.contains(selection) else {
                core.snippets.create()
                return
            }
            core.snippets.paste(snippetResults[selection])
        case .snippetEditor, .quicklinkEditor:
            return
        case .quicklinks:
            quicklinkScreen(items: quicklinkResults, selection: selection).activate()
        case .emoji:
            emojiScreen(sections: emojiSections, selection: selection).activate()
        case .uninstall:
            uninstallScreen(items: uninstallResults, selection: selection).activate()
        }
    }

    private func activateLauncherApp(_ app: AppEntry, in apps: [AppEntry], offset: Int) {
        let wasSelected = selectedAppEntry == app
        if let index = apps.firstIndex(of: app) { vm.selection = index + offset }
        if !wasSelected { inlineArgumentValues.removeAll(keepingCapacity: true) }
        launchApp(app)
    }

    private func launchApp(_ app: AppEntry) {
        core.launcher.launch(
            app,
            searchQuery: vm.query,
            inlineArgumentValues: inlineArgumentValues)
    }
}

/// The active sub-screen label in the footer; it opens the same app menu as the root footer button.
private struct PaletteModeMenuButton: View {
    let mode: PaletteMode
    let title: String?
    let action: () -> Void
    @State private var hovered = false

    private var iconTint: Color {
        switch mode {
        case .launcher: return Theme.Colors.launcherAccent
        case .clipboard: return Theme.Colors.clipboardAccent
        case .emoji: return Theme.Colors.emojiAccent
        case .snippets, .snippetEditor, .quicklinks, .quicklinkEditor:
            return Theme.Colors.systemAccent
        case .uninstall: return Theme.Colors.textSecondary
        }
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.md) {
                FeatureIcon(
                    systemImage: mode.systemImage,
                    tint: iconTint,
                    size: Theme.Size.rowIcon
                )
                Text(title ?? mode.title)
                    .font(Theme.Typography.calloutMedium)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: Theme.Size.menuButton)
            .contentShape(Capsule())
            .background(
                Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear)
            )
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering { NSCursor.arrow.set() }
        }
        .paletteFooterSurface(in: Capsule())
    }
}

/// The footer's menu circle; hover lives here so a mouse sweep never re-renders the palette body.
private struct MenuCircleButton: View {
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 3) {
                Capsule().frame(width: 14, height: 1.5)
                Capsule().frame(width: 8, height: 1.5)
            }
            .foregroundStyle(Theme.Colors.textSecondary)
            .frame(width: Theme.Size.menuButton, height: Theme.Size.menuButton)
            .background(Circle().fill(hovered ? Theme.Colors.rowHover : Color.clear))
            .contentShape(.circle)
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .paletteFooterSurface(in: Circle())
    }
}

extension View {
    /// Faint mouse-hover highlight for a palette row, lit only while the pointer is physically moving (`hoverHighlightArmed`) so it never fires on open or when rows slide under a still pointer during keyboard nav. Independent of the keyboard selection, so both coexist.
    func armedHover(_ hovered: Binding<Bool>) -> some View {
        onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active: hovered.wrappedValue = AppCore.shared.palette.hoverHighlightArmed
            case .ended: hovered.wrappedValue = false
            }
        }
    }
}

struct EmptyResults: View {
    let text: String
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass").font(Theme.Typography.largeTitle)
                .symbolRenderingMode(.hierarchical).foregroundStyle(.tertiary)
            Text(text).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A slot in the compact bar's favorites strip: a launchable app, or the "…" overflow that expands the window.
enum CompactFavoriteSlot {
    case app(AppEntry)
    case more

    // Stable identity so a slot keeps its icon tied to its app, not its position, when favorites reorder.
    var id: String {
        switch self {
        case .app(let app): return app.id
        case .more: return "__opencast.more__"
        }
    }
}

/// The compact bar's favorites strip — up to 5 icon buttons, ⌘1–⌘5 mirrored in each tooltip.
private struct CompactFavoritesRow: View {
    let slots: [CompactFavoriteSlot]
    let onLaunch: (AppEntry) -> Void
    let onOverflow: () -> Void

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(slots.enumerated()), id: \.element.id) { index, slot in
                switch slot {
                case .app(let app):
                    CompactFavoriteButton(
                        title: app.name, shortcutIndex: index + 1, action: { onLaunch(app) }
                    ) {
                        AppIconView(app: app)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                    }
                case .more:
                    CompactFavoriteButton(
                        title: "Show all", shortcutIndex: index + 1, action: onOverflow
                    ) {
                        Image(systemName: "ellipsis")
                            .font(Theme.Typography.iconTiny)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
                            .background(
                                RoundedRectangle(cornerRadius: 6, style: .continuous)
                                    .fill(Theme.Colors.controlSurface)
                                    .padding(Theme.Spacing.xxs)
                            )
                    }
                }
            }
        }
    }
}

/// A single compact favorite icon with a custom tooltip and its position-based shortcut.
private struct CompactFavoriteButton<Content: View>: View {
    let title: String
    let shortcutIndex: Int
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            content
                .contentShape(RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous))
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hovered = hovering
            if hovering { NSCursor.arrow.set() }
        }
        .background {
            CompactFavoriteTooltipPresenter(
                isPresented: hovered, title: title, shortcutIndex: shortcutIndex
            )
        }
    }
}

private struct CompactFavoriteTooltip: View {
    let title: String
    let shortcutIndex: Int

    var body: some View {
        HStack(spacing: Theme.Spacing.xl) {
            Text(title)
                .font(Theme.Typography.headlineSemibold)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
            HStack(spacing: Theme.Spacing.xxs) {
                KeyCapChip(text: "⌘")
                KeyCapChip(text: "\(shortcutIndex)")
            }
        }
        .padding(.horizontal, Theme.Spacing.lg)
        .padding(.vertical, Theme.Spacing.sm)
        .background {
            RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                .fill(Theme.Colors.tooltipSurface)
                .overlay {
                    RoundedRectangle(cornerRadius: Theme.Radius.menuPanel, style: .continuous)
                        .strokeBorder(Theme.Colors.border, lineWidth: 1)
                }
        }
        .fixedSize()
    }
}

private struct CompactFavoriteTooltipPresenter: NSViewRepresentable {
    let isPresented: Bool
    let title: String
    let shortcutIndex: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(title: title, shortcutIndex: shortcutIndex)
    }

    func makeNSView(context: Context) -> NSView {
        TooltipAnchorView()
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        context.coordinator.isPresented = isPresented
        context.coordinator.title = title
        context.coordinator.shortcutIndex = shortcutIndex
        if isPresented {
            DispatchQueue.main.async { context.coordinator.present(from: nsView) }
        } else {
            context.coordinator.dismiss()
        }
    }

    static func dismantleNSView(_ nsView: NSView, coordinator: Coordinator) {
        coordinator.dismiss()
    }

    @MainActor final class Coordinator: NSObject {
        var isPresented = false
        var title: String
        var shortcutIndex: Int
        private let panel: NSPanel
        private let host: NSHostingView<CompactFavoriteTooltip>

        init(title: String, shortcutIndex: Int) {
            self.title = title
            self.shortcutIndex = shortcutIndex
            host = NSHostingView(
                rootView: CompactFavoriteTooltip(title: title, shortcutIndex: shortcutIndex))
            panel = NSPanel(
                contentRect: .zero,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered,
                defer: false
            )
            super.init()
            panel.contentView = host
            panel.isOpaque = false
            panel.backgroundColor = .clear
            panel.hasShadow = true
            panel.ignoresMouseEvents = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.isReleasedWhenClosed = false
        }

        func present(from anchor: NSView) {
            guard isPresented, anchor.window != nil else { return }
            host.rootView = CompactFavoriteTooltip(title: title, shortcutIndex: shortcutIndex)
            host.layoutSubtreeIfNeeded()
            let size = host.fittingSize
            guard size.width > 0, size.height > 0,
                let screen = anchor.window?.screen ?? NSScreen.main
            else { return }
            let anchorRect = anchor.window!.convertToScreen(anchor.convert(anchor.bounds, to: nil))
            let visible = screen.visibleFrame
            let gap = Theme.Spacing.sm
            var origin = NSPoint(
                x: anchorRect.midX - size.width / 2,
                y: anchorRect.maxY + gap
            )
            if origin.y + size.height > visible.maxY {
                origin.y = anchorRect.minY - size.height - gap
            }
            origin.x = min(max(origin.x, visible.minX + gap), visible.maxX - size.width - gap)
            panel.setFrame(NSRect(origin: origin, size: size), display: false)
            panel.orderFrontRegardless()
        }

        func dismiss() {
            panel.orderOut(nil)
        }
    }

    private final class TooltipAnchorView: NSView {
        override func hitTest(_ point: NSPoint) -> NSView? { nil }
    }
}
