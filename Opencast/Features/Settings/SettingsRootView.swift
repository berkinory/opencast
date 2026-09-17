import AppKit
import SwiftUI

extension Notification.Name {
    /// Navigates an already-open Settings window without rebuilding its SwiftUI tree.
    static let opencastSelectSettingsRoute = Notification.Name("OpencastSelectSettingsRoute")
}

struct SettingsRoute: Hashable, Sendable {
    let tab: SettingsTab
    var destination: SettingsDestination? = nil

    static let general = SettingsRoute(tab: .general)
    static let about = SettingsRoute(tab: .about)
}

enum SettingsTab: Int, CaseIterable, Identifiable, Sendable {
    case general, hyperKey, launcher, commands, clipboard, snippets, quicklinks, emoji, calculator
    case windowManagement, about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .hyperKey: return "Hyper Key"
        case .launcher: return "Launcher"
        case .commands: return "Commands"
        case .clipboard: return "Clipboard"
        case .snippets: return "Snippets"
        case .quicklinks: return "Quicklinks"
        case .emoji: return "Emoji"
        case .calculator: return "Calculator"
        case .windowManagement: return "Window"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .hyperKey: return "capslock"
        case .launcher: return "command"
        case .commands: return "terminal"
        case .clipboard: return "clipboard"
        case .snippets: return "text.quote"
        case .quicklinks: return "link"
        case .emoji: return "face.smiling"
        case .calculator: return "function"
        case .windowManagement: return "macwindow.and.cursorarrow"
        case .about: return "info.circle"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .general, .hyperKey, .launcher, .commands: return .preferences
        case .clipboard, .snippets, .quicklinks, .emoji, .calculator, .windowManagement:
            return .features
        case .about: return .about
        }
    }

    var tint: Color {
        switch self {
        case .general: return Theme.Colors.systemAccent
        case .hyperKey: return Theme.Colors.systemAccent
        case .launcher: return Theme.Colors.launcherAccent
        case .commands: return Theme.Colors.systemAccent
        case .clipboard: return Theme.Colors.clipboardAccent
        case .snippets: return Theme.Colors.systemAccent
        case .quicklinks: return Theme.Colors.launcherAccent
        case .emoji: return Theme.Colors.emojiAccent
        case .calculator: return Theme.Colors.calculatorAccent
        case .windowManagement: return Theme.Colors.launcherAccent
        case .about: return Theme.Colors.brand
        }
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case preferences, features, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .features: return "Features"
        case .about: return ""
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.group == self }
    }
}

@MainActor
private final class SettingsNavigationModel: ObservableObject {
    @Published var route: SettingsRoute

    init(route: SettingsRoute) {
        self.route = route
    }

    func navigate(to route: SettingsRoute) {
        self.route = route
    }

    func select(_ tab: SettingsTab) {
        navigate(to: SettingsRoute(tab: tab))
    }
}

struct SettingsRootView: View {
    @StateObject private var navigation: SettingsNavigationModel
    @State private var searchQuery = ""

    private struct SearchEntry: Identifiable {
        let record: SettingsSearchRecord
        let route: SettingsRoute
        var id: String { record.id }
    }

    private struct SidebarGroup: Identifiable {
        let group: SettingsGroup
        let tabs: [SettingsTab]
        var id: String { group.id }
    }

    init(initialRoute: SettingsRoute = .general) {
        _navigation = StateObject(wrappedValue: SettingsNavigationModel(route: initialRoute))
    }

    private var sidebarGroups: [SidebarGroup] {
        SettingsGroup.allCases.map { SidebarGroup(group: $0, tabs: $0.tabs) }
    }

    private var searchEntries: [SearchEntry] {
        let settings = [
            SearchEntry(
                record: .init(
                    id: "tab-general", title: "General", detail: "Startup and permissions", breadcrumb: "Preferences",
                    keywords: ["login", "menu bar", "accessibility"]), route: .init(tab: .general)),
            SearchEntry(
                record: .init(
                    id: "launch-at-login", title: "Launch at login", detail: "Start automatically after signing in",
                    breadcrumb: "General · Startup", keywords: ["startup", "open on login"]),
                route: .init(tab: .general, destination: .launchAtLogin)),
            SearchEntry(
                record: .init(
                    id: "show-in-menu-bar", title: "Menu bar icon",
                    detail: "Keep the icon visible while global shortcuts continue working",
                    breadcrumb: "General · Startup", keywords: ["menu bar", "status item"]),
                route: .init(tab: .general, destination: .showInMenuBar)),
            SearchEntry(
                record: .init(
                    id: "accessibility", title: "Accessibility access",
                    detail: "Allow window control and reliable paste focus", breadcrumb: "General · Permissions",
                    keywords: ["permission", "access", "window control"]),
                route: .init(tab: .general, destination: .accessibility)),
            SearchEntry(
                record: .init(
                    id: "tab-hyper-key", title: "Hyper Key", detail: "Turn one physical key into a shortcut modifier",
                    breadcrumb: "Preferences", keywords: ["keyboard", "modifier", "caps lock"]),
                route: .init(tab: .hyperKey)),
            SearchEntry(
                record: .init(
                    id: "tab-launcher", title: "Launcher",
                    detail: "Search behavior, appearance, and remembered results", breadcrumb: "Preferences",
                    keywords: ["apps", "search", "ranking"]), route: .init(tab: .launcher)),
            SearchEntry(
                record: .init(
                    id: "launcher-shortcut", title: "Open launcher", detail: "Assign the global launcher shortcut",
                    breadcrumb: "Launcher · Shortcut", keywords: ["hotkey", "keyboard shortcut"]),
                route: .init(tab: .launcher, destination: .launcherShortcut)),
            SearchEntry(
                record: .init(
                    id: "compact-mode", title: "Compact mode",
                    detail: "Choose how much appears when the launcher opens", breadcrumb: "Launcher · Appearance",
                    keywords: ["small", "palette size"]), route: .init(tab: .launcher, destination: .compactMode)),
            SearchEntry(
                record: .init(
                    id: "compact-favorites", title: "Compact favorites",
                    detail: "Show favorite apps in the compact bar", breadcrumb: "Launcher · Appearance",
                    keywords: ["favorites", "pinned"]), route: .init(tab: .launcher, destination: .compactFavorites)),
            SearchEntry(
                record: .init(
                    id: "return-to-launcher", title: "Pop to Root Search",
                    detail: "Choose when a closed palette returns to the main search",
                    breadcrumb: "Launcher · Behavior", keywords: ["reset", "timeout", "root"]),
                route: .init(tab: .launcher, destination: .returnToLauncher)),
            SearchEntry(
                record: .init(
                    id: "search-scopes", title: "Search scopes", detail: "Choose which application folders are indexed",
                    breadcrumb: "Launcher · Search", keywords: ["folders", "directories", "applications"]),
                route: .init(tab: .launcher, destination: .searchScopes)),
            SearchEntry(
                record: .init(
                    id: "tab-commands", title: "Commands", detail: "Show commands and assign their shortcuts",
                    breadcrumb: "Preferences", keywords: ["actions", "hotkeys"]), route: .init(tab: .commands)),
            SearchEntry(
                record: .init(
                    id: "tab-clipboard", title: "Clipboard", detail: "History retention and private applications",
                    breadcrumb: "Features", keywords: ["paste", "copy", "history"]), route: .init(tab: .clipboard)),
            SearchEntry(
                record: .init(
                    id: "clipboard-retention", title: "Clipboard retention",
                    detail: "Choose how long saved clips remain", breadcrumb: "Clipboard · History",
                    keywords: ["expiry", "keep", "delete"]),
                route: .init(tab: .clipboard, destination: .clipboardRetention)),
            SearchEntry(
                record: .init(
                    id: "clipboard-excluded-apps", title: "Private applications",
                    detail: "Never record clipboard changes from selected apps", breadcrumb: "Clipboard · Privacy",
                    keywords: ["exclude", "ignore", "sensitive"]),
                route: .init(tab: .clipboard, destination: .clipboardExcludedApps)),
            SearchEntry(
                record: .init(
                    id: "clipboard-clear-history", title: "Clear clipboard history",
                    detail: "Permanently remove every saved clip and image", breadcrumb: "Clipboard · History",
                    keywords: ["delete", "clear", "remove"]),
                route: .init(tab: .clipboard, destination: .clipboardClearHistory)),
            SearchEntry(
                record: .init(
                    id: "tab-snippets", title: "Snippets", detail: "Reusable text and keyword expansion",
                    breadcrumb: "Features", keywords: ["text", "templates", "expansion"]), route: .init(tab: .snippets)),
            SearchEntry(
                record: .init(
                    id: "snippet-disabled-apps", title: "Disabled snippet applications",
                    detail: "Prevent keyword expansion in selected apps", breadcrumb: "Snippets · Privacy",
                    keywords: ["exclude", "ignore"]), route: .init(tab: .snippets, destination: .snippetDisabledApps)),
            SearchEntry(
                record: .init(
                    id: "tab-quicklinks", title: "Quicklinks", detail: "Saved URLs, files, and folders",
                    breadcrumb: "Features", keywords: ["links", "bookmarks", "paths"]), route: .init(tab: .quicklinks)),
            SearchEntry(
                record: .init(
                    id: "tab-emoji", title: "Emoji & Symbols", detail: "Search emoji and symbols from anywhere",
                    breadcrumb: "Features", keywords: ["unicode", "characters", "keyboard"]), route: .init(tab: .emoji)),
            SearchEntry(
                record: .init(
                    id: "emoji-skin-tone", title: "Preferred skin tone",
                    detail: "Choose the default tone for supported emoji", breadcrumb: "Emoji & Symbols · Appearance",
                    keywords: ["emoji", "appearance"]), route: .init(tab: .emoji, destination: .emojiSkinTone)),
            SearchEntry(
                record: .init(
                    id: "tab-calculator", title: "Calculator", detail: "Calculate directly from launcher search",
                    breadcrumb: "Features", keywords: ["math", "conversion", "dates"]), route: .init(tab: .calculator)),
            SearchEntry(
                record: .init(
                    id: "currency-conversion", title: "Currency conversion",
                    detail: "Convert between supported fiat currencies", breadcrumb: "Calculator · Conversions",
                    keywords: ["money", "exchange", "fiat"]),
                route: .init(tab: .calculator, destination: .currencyConversion)),
            SearchEntry(
                record: .init(
                    id: "crypto-conversion", title: "Crypto conversion",
                    detail: "Include supported cryptocurrencies in conversions", breadcrumb: "Calculator · Conversions",
                    keywords: ["bitcoin", "crypto", "exchange"]),
                route: .init(tab: .calculator, destination: .cryptoConversion)),
            SearchEntry(
                record: .init(
                    id: "tab-window", title: "Window Management", detail: "Move and resize the frontmost window",
                    breadcrumb: "Features", keywords: ["tiling", "resize", "move"]),
                route: .init(tab: .windowManagement)),
        ]
        let windowCommands = WindowCommandCatalog.all.map { command in
            SearchEntry(
                record: .init(
                    id: command.entryID,
                    title: command.name,
                    detail: "Assign a shortcut or hide this window action",
                    breadcrumb: "Commands · Window commands",
                    keywords: ["window", "shortcut", "move", "resize"]),
                route: .init(
                    tab: .commands,
                    destination: .shortcutEntry(
                        entryID: command.entryID, kind: command.kind.rawValue)))
        }
        return settings + windowCommands
    }

    private var searchResults: [SearchEntry] {
        let entries = searchEntries
        let records = Dictionary(uniqueKeysWithValues: entries.map { ($0.record.id, $0) })
        return SettingsSearchIndex.search(searchQuery, in: entries.map(\.record)).compactMap {
            records[$0.record.id]
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelSurface.ignoresSafeArea())
        .background(VisualEffectView().ignoresSafeArea())
        .tint(Theme.Colors.textSecondary)
        .onReceive(NotificationCenter.default.publisher(for: .opencastSelectSettingsRoute)) {
            note in
            guard let route = note.object as? SettingsRoute else { return }
            navigation.navigate(to: route)
        }
    }

    private var content: some View {
        pane(for: navigation.route.tab)
            .environment(\.settingsDestination, navigation.route.destination)
            .id(navigation.route.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .hyperKey: HyperKeySettingsView()
        case .launcher: LauncherSettingsView()
        case .commands: CommandsSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .snippets: SnippetSettingsView()
        case .quicklinks: QuicklinkSettingsView()
        case .emoji: EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
        case .windowManagement: WindowManagementSettingsView()
        case .about: AboutView()
        }
    }

    private var sidebar: some View {
        VStack(spacing: 0) {
            searchField
                .padding(.horizontal, Theme.Settings.Layout.sidebarInset)
                .padding(.top, Theme.Settings.Layout.sidebarTopInset)
                .padding(.bottom, Theme.Spacing.md)

            ScrollView {
                Group {
                    if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        VStack(alignment: .leading, spacing: Theme.Settings.Layout.groupSpacing) {
                            ForEach(sidebarGroups) { section in
                                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                                    if !section.group.title.isEmpty {
                                        Text(section.group.title.uppercased())
                                            .font(Theme.Typography.caption2Semibold)
                                            .foregroundStyle(Theme.Colors.textTertiary)
                                            .tracking(0.6)
                                            .padding(.horizontal, Theme.Spacing.lg)
                                    }

                                    ForEach(section.tabs) { item in
                                        sidebarRow(item)
                                            .padding(.horizontal, Theme.Settings.Layout.sidebarInset)
                                    }
                                }
                            }
                        }
                    } else if searchResults.isEmpty {
                        Text("No matching settings.")
                            .font(Theme.Typography.callout)
                            .foregroundStyle(Theme.Colors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, Theme.Spacing.lg)
                            .padding(.top, Theme.Spacing.lg)
                    } else {
                        VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                            ForEach(searchResults) { entry in
                                searchResultRow(entry)
                            }
                        }
                    }
                }
                .padding(.bottom, Theme.Spacing.xxl)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .overlayScroller(disablesElasticity: true)
        }
        .frame(width: Theme.Settings.Size.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                Theme.Settings.Colors.sidebarDimming
                Rectangle()
                    .fill(Theme.Settings.Colors.sidebarSeparator)
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }

    private var searchField: some View {
        HStack(spacing: Theme.Spacing.sm) {
            Image(systemName: "magnifyingglass")
                .font(Theme.Typography.iconSmall)
                .foregroundStyle(Theme.Colors.textTertiary)
            TextField("Search Settings", text: $searchQuery)
                .textFieldStyle(.plain)
                .font(Theme.Typography.callout)
            if !searchQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(Theme.Colors.textTertiary)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Settings.Size.sidebarRowHeight)
        .background(
            RoundedRectangle(cornerRadius: Theme.Settings.Radius.controlIcon, style: .continuous)
                .fill(Theme.Settings.Colors.searchFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Theme.Settings.Radius.controlIcon, style: .continuous)
                .strokeBorder(Theme.Settings.Colors.searchStroke, lineWidth: 1)
        )
    }

    private func searchResultRow(_ entry: SearchEntry) -> some View {
        Button {
            navigation.navigate(to: entry.route)
            searchQuery = ""
        } label: {
            HStack(spacing: Theme.Spacing.md) {
                Image(systemName: entry.route.tab.systemImage)
                    .font(Theme.Typography.iconSmall)
                    .foregroundStyle(entry.route.tab.tint)
                    .frame(width: Theme.Settings.Size.sidebarIcon)
                VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                    Text(entry.record.title)
                        .font(Theme.Typography.calloutMedium)
                        .foregroundStyle(Theme.Colors.textPrimary)
                        .lineLimit(1)
                    Text(entry.record.breadcrumb)
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textTertiary)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Settings.Size.sidebarRowHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        SidebarRow(
            title: item.title,
            systemImage: item.systemImage,
            tint: item.tint,
            isSelected: navigation.route.tab == item
        ) {
            navigation.select(item)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.iconMediumSmall)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? tint : Theme.Colors.textSecondary)
                    .frame(width: Theme.Settings.Size.sidebarIcon)

                Text(title)
                    .font(Theme.Typography.callout.weight(isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Settings.Size.sidebarRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.navigation,
                    style: .continuous
                )
                .fill(rowFill)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: Theme.Spacing.xxs,
                            height: Theme.Settings.Size.sidebarSelectionHeight
                        )
                        .padding(.leading, Theme.Spacing.xs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .opacity(focused ? 1 : 0.96)
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if isSelected { return Theme.Settings.Colors.navigationSelection }
        if hovering || focused { return Theme.Settings.Colors.navigationHover }
        return .clear
    }
}
