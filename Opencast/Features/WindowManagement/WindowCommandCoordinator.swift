import AppKit

@MainActor
final class WindowCommandCoordinator {
    private let settings: AppSettings
    private let mover: WindowMover
    private let paletteIsVisible: () -> Bool
    private let previousApplication: () -> NSRunningApplication?
    private let hidePalette: (Bool) -> Void

    init(
        settings: AppSettings,
        mover: WindowMover,
        paletteIsVisible: @escaping () -> Bool,
        previousApplication: @escaping () -> NSRunningApplication?,
        hidePalette: @escaping (Bool) -> Void
    ) {
        self.settings = settings
        self.mover = mover
        self.paletteIsVisible = paletteIsVisible
        self.previousApplication = previousApplication
        self.hidePalette = hidePalette
    }

    func run(_ id: WindowCommand.ID) {
        guard settings.windowManagementEnabled else { return }
        let wasVisible = paletteIsVisible()
        let target = wasVisible ? previousApplication() : NSWorkspace.shared.frontmostApplication
        if wasVisible { hidePalette(true) }
        _ = mover.perform(
            id,
            target: target,
            gap: WindowMover.currentGap(
                respectSystemMargins: settings.windowRespectSystemMargins)
        )
    }
}
