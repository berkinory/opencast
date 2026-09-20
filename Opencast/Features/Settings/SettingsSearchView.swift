import Foundation

enum SettingsDestination: Hashable, Sendable {
    case launcherShortcut
    case searchScopes
    case learnedRanking
    case compactMode
    case compactFavorites
    case launchAtLogin
    case showInMenuBar
    case returnToLauncher
    case clipboardShortcut
    case clipboardRetention
    case clipboardExcludedApps
    case clipboardClearHistory
    case snippetDisabledApps
    case snippetExpandAfterSpace
    case quicklinksEnabled
    case emojiShortcut
    case emojiSkinTone
    case accessibility
    case currencyConversion
    case cryptoConversion
    case exchangeRates
    case shortcutEntry(entryID: String, kind: String)

    var anchorID: String {
        switch self {
        case .launcherShortcut: return "launcher-shortcut"
        case .searchScopes: return "search-scopes"
        case .learnedRanking: return "learned-ranking"
        case .compactMode: return "compact-mode"
        case .compactFavorites: return "compact-favorites"
        case .launchAtLogin: return "launch-at-login"
        case .showInMenuBar: return "show-in-menu-bar"
        case .returnToLauncher: return "return-to-launcher"
        case .clipboardShortcut: return "clipboard-shortcut"
        case .clipboardRetention: return "clipboard-retention"
        case .clipboardExcludedApps: return "clipboard-excluded-apps"
        case .clipboardClearHistory: return "clipboard-clear-history"
        case .snippetDisabledApps: return "snippet-disabled-apps"
        case .snippetExpandAfterSpace: return "snippet-expand-after-space"
        case .quicklinksEnabled: return "quicklinks-enabled"
        case .emojiShortcut: return "emoji-shortcut"
        case .emojiSkinTone: return "emoji-skin-tone"
        case .accessibility: return "accessibility"
        case .currencyConversion: return "currency-conversion"
        case .cryptoConversion: return "crypto-conversion"
        case .exchangeRates: return "exchange-rates"
        case .shortcutEntry(let entryID, _): return "shortcut-entry:\(entryID)"
        }
    }
}
