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
    /// Changes when an action reorders the list under the selection (pinning a clip lifts it into the Pinned section), so the list scrolls the highlight back into view.
    @Published var followToken = UUID()
    /// Set by the compact bar's "…" overflow to expand into the full launcher without a query; cleared on every `prepare`.
    @Published var forceExpanded = false
    private var launcherQueryForReturn: String?
    /// The app a paste would land in, mirrored from `PaletteWindowController.previousApp` on every show. Deliberately *not* cleared by `prepare` — pop-to-root resets the screen, not the paste target.
    @Published var pasteTarget: PasteTarget?
    /// Gates the mouse-hover highlight: true only while the pointer is physically moving (armed on `.mouseMoved`, disarmed on any `.keyDown` in `PalettePanel.sendEvent`). Plain, not `@Published` — read at hover time, never drives a re-render.
    var hoverHighlightArmed = false
    /// The main search field's SwiftUI frame, used by `PalettePanel` to settle the cursor after AppKit has applied its cursor rects.
    var searchFieldFrame: CGRect = .zero
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
        onCommandEnter = nil
        hoverHighlightArmed = false
        menuOpen = false
        focusToken = UUID()
        resetToken = UUID()
        selectQueryToken = UUID()
    }

    func postFeedback(_ message: String, tone: PaletteFeedback.Tone = .success) {
        feedback = PaletteFeedback(message: message, tone: tone)
    }
}
