import AppKit

@MainActor
final class SnippetCoordinator {
    private let store: SnippetStore
    private let settings: AppSettings
    private let palette: PaletteViewModel
    private let previousApplication: () -> NSRunningApplication?
    private let hidePalette: (Bool) -> Void

    init(
        store: SnippetStore,
        settings: AppSettings,
        palette: PaletteViewModel,
        previousApplication: @escaping () -> NSRunningApplication?,
        hidePalette: @escaping (Bool) -> Void
    ) {
        self.store = store
        self.settings = settings
        self.palette = palette
        self.previousApplication = previousApplication
        self.hidePalette = hidePalette
    }

    func create() {
        guard settings.snippetsEnabled else { return }
        palette.enterSubscreen(.snippetEditor)
    }

    func edit(_ snippet: Snippet) {
        guard settings.snippetsEnabled else { return }
        palette.enterSubscreen(.snippetEditor)
        palette.snippetEditingID = snippet.id
        palette.snippetEditorReturnsToSearch = true
    }

    func search() {
        guard settings.snippetsEnabled else { return }
        palette.enterSubscreen(.snippets)
    }

    func exitEditor() {
        if palette.snippetEditorReturnsToSearch {
            palette.mode = .snippets
            palette.query = ""
            palette.selection = 0
            palette.snippetEditingID = nil
            palette.snippetEditorReturnsToSearch = false
            palette.focusToken = UUID()
            palette.resetToken = UUID()
        } else {
            palette.returnToLauncher()
        }
    }

    func paste(_ snippet: Snippet) {
        let previous = previousApplication()
        hidePalette(false)
        Paster.pasteString(snippet.content, previousApp: previous)
    }

    func copy(_ snippet: Snippet) {
        Paster.copyString(snippet.content)
        palette.postFeedback("Copied snippet")
    }

    func togglePinned(_ snippet: Snippet) {
        do {
            try store.togglePinned(snippet)
        } catch {
            palette.postFeedback("Could not save snippet", tone: .error)
            return
        }
        palette.selection = store.rowIndex(of: snippet, in: palette.query) ?? 0
    }

    func duplicate(_ snippet: Snippet) {
        do {
            _ = try store.duplicate(snippet)
            palette.postFeedback("Duplicated snippet")
        } catch {
            palette.postFeedback("Could not duplicate snippet", tone: .error)
        }
    }

    func delete(_ snippet: Snippet) {
        do {
            try store.delete(snippet)
        } catch {
            palette.postFeedback("Could not delete snippet", tone: .error)
            return
        }
        palette.selection = 0
        palette.postFeedback("Deleted snippet")
    }
}
