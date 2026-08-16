import Foundation

/// App-internal launcher actions surfaced as a "Commands" category; each is a synthetic `AppEntry` (kind `.command`, no bundle ID) so existing `AppEntry` plumbing applies, with dispatch in `AppCore.runCommand`.
enum CommandID: String, CaseIterable, Sendable {
    case clipboardHistory = "command:clipboard-history"
    case searchSnippets = "command:search-snippets"
    case createSnippet = "command:create-snippet"
    case searchQuicklinks = "command:search-quicklinks"
    case createQuicklink = "command:create-quicklink"
    case searchEmoji = "command:search-emoji"
    case store = "command:store"
    case importExtension = "command:import-extension"
    case settings = "command:settings"
    case checkForUpdates = "command:check-for-updates"
    case quit = "command:quit"
    case caffeinate = "command:caffeinate"
    case decaffeinate = "command:decaffeinate"
    case caffeinateFor = "command:caffeinate-for"

    var name: String {
        switch self {
        case .clipboardHistory: return "Clipboard History"
        case .searchSnippets: return "Search Snippets"
        case .createSnippet: return "Create Snippet"
        case .searchQuicklinks: return "Search Quicklinks"
        case .createQuicklink: return "Create Quicklink"
        case .searchEmoji: return "Search Emoji & Symbols"
        case .store: return "Store"
        case .importExtension: return "Import Extension"
        case .settings: return "Settings"
        case .checkForUpdates: return "Check for Updates"
        case .quit: return "Quit Opencast"
        case .caffeinate: return "Caffeinate"
        case .decaffeinate: return "Decaffeinate"
        case .caffeinateFor: return "Caffeinate For"
        }
    }

    var sfSymbol: String {
        switch self {
        case .clipboardHistory: return "clipboard"
        case .searchSnippets: return "doc.text.magnifyingglass"
        case .createSnippet: return "square.and.pencil"
        case .searchQuicklinks: return "link"
        case .createQuicklink: return "link.badge.plus"
        case .searchEmoji: return "face.smiling"
        case .store: return "puzzlepiece.extension"
        case .importExtension: return "tray.and.arrow.down"
        case .settings: return "slider.horizontal.3"
        case .checkForUpdates: return "arrow.triangle.2.circlepath"
        case .quit: return "xmark.circle"
        case .caffeinate: return "cup.and.saucer.fill"
        case .decaffeinate: return "cup.and.saucer"
        case .caffeinateFor: return "timer"
        }
    }

    var inlineArguments: [InlineArgument] {
        guard self == .caffeinateFor else { return [] }
        return [
            InlineArgument(id: "hours", placeholder: "Hours", help: "Whole hours"),
            InlineArgument(id: "minutes", placeholder: "Minutes", help: "Whole minutes"),
            InlineArgument(id: "seconds", placeholder: "Seconds", help: "Whole seconds"),
        ]
    }

    var isRunnable: Bool {
        switch self {
        case .store, .importExtension, .caffeinate, .decaffeinate, .caffeinateFor: return true
        default: return false
        }
    }

    var hotKeyAction: HotKeyAction? {
        switch self {
        case .clipboardHistory: return .toggleClipboard
        case .searchEmoji: return .toggleEmoji
        default: return nil
        }
    }

    var primaryActionTitle: String {
        switch self {
        case .clipboardHistory: return "Open Clipboard History"
        case .searchSnippets: return "Open Snippets"
        case .createSnippet: return "Create Snippet"
        case .searchQuicklinks: return "Open Quicklinks"
        case .createQuicklink: return "Create Quicklink"
        case .searchEmoji: return "Open Emoji & Symbols"
        case .store: return "Open Store"
        case .importExtension: return "Import Extension"
        case .settings: return "Open Settings"
        case .checkForUpdates: return "Check for Updates"
        case .quit: return "Quit Opencast"
        case .caffeinate, .decaffeinate, .caffeinateFor: return "Run Command"
        }
    }
}

enum CommandRegistry {
    /// Sorted by name to keep the AppIndex sort invariant; the URL is a placeholder since commands are never launched from disk.
    nonisolated static let all: [AppEntry] =
        CommandID.allCases
        .map { id in
            AppEntry(
                id: id.rawValue, name: id.name,
                url: URL(
                    string: "opencast://" + id.rawValue.replacingOccurrences(of: ":", with: "/"))!,
                bundleID: nil, kind: .command)
        }
        .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }

    static func command(for entry: AppEntry) -> CommandID? {
        CommandID(rawValue: entry.id)
    }
}
