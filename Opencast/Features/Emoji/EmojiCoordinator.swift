import AppKit

@MainActor
final class EmojiCoordinator {
    private let frequent: FrequentEmojiStore
    private let settings: AppSettings
    private let previousApplication: () -> NSRunningApplication?
    private let hidePalette: (Bool) -> Void
    private let pasteKeepingOpen: (String) -> Void

    init(
        frequent: FrequentEmojiStore,
        settings: AppSettings,
        previousApplication: @escaping () -> NSRunningApplication?,
        hidePalette: @escaping (Bool) -> Void,
        pasteKeepingOpen: @escaping (String) -> Void
    ) {
        self.frequent = frequent
        self.settings = settings
        self.previousApplication = previousApplication
        self.hidePalette = hidePalette
        self.pasteKeepingOpen = pasteKeepingOpen
    }

    func paste(_ entry: EmojiEntry) {
        record(entry)
        let previous = previousApplication()
        hidePalette(false)
        Paster.pasteString(entry.display(tone: settings.emojiSkinTone), previousApp: previous)
    }

    func copy(_ entry: EmojiEntry) {
        record(entry)
        hidePalette(false)
        Paster.copyString(entry.display(tone: settings.emojiSkinTone))
    }

    func pasteAndKeepOpen(_ entry: EmojiEntry) {
        record(entry)
        pasteKeepingOpen(entry.display(tone: settings.emojiSkinTone))
    }

    private func record(_ entry: EmojiEntry) {
        frequent.record(entry.glyph)
    }
}
