import SwiftUI

@MainActor
struct UninstallPaletteScreen: PaletteScreen {
    let items: [LeftoverItem]
    let selection: Int
    let scrollIntent: ListScrollIntent?
    let session: UninstallSession
    let coordinator: UninstallCoordinator
    let onSelect: (Int) -> Void
    let onOpenActions: () -> Void

    var itemCount: Int {
        session.phase == .selecting ? items.count : 0
    }

    var actionsContent: PopoverMenuContent? {
        guard session.phase == .selecting, !items.isEmpty else { return nil }
        return UninstallActionsMenu.content(
            session: session, visible: items, selection: selection, coordinator: coordinator)
    }

    var body: some View {
        Group {
            switch session.phase {
            case .removing(let permanently):
                UninstallProgressView(
                    name: session.target?.name ?? "Application", permanently: permanently)
            case .done(let outcome):
                UninstallSummaryView(
                    name: session.target?.name ?? "Application", outcome: outcome)
            case .selecting:
                selectionView
            }
        }
    }

    @discardableResult
    func activate() -> Bool {
        switch session.phase {
        case .selecting:
            coordinator.remove()
        case .removing:
            return false
        case .done:
            coordinator.finish()
        }
        return true
    }

    @discardableResult
    func reveal() -> Bool {
        guard items.indices.contains(selection) else { return false }
        coordinator.reveal(items[selection])
        return true
    }

    @ViewBuilder
    private var selectionView: some View {
        if session.items.isEmpty {
            EmptyResults(
                text: session.isScanning
                    ? "Looking for files to remove…" : "Nothing found to remove")
        } else if items.isEmpty {
            EmptyResults(text: "No files match")
        } else {
            VStack(spacing: 0) {
                UninstallStatusLine(
                    checkedCount: session.checkedItems.count,
                    totalCount: session.items.count,
                    checkedSize: session.checkedSize
                )
                UninstallList(
                    items: items,
                    selection: selection,
                    isChecked: session.isChecked,
                    appIcon: session.target.flatMap { IconCache.cached(forFile: $0.url.path) },
                    scroll: scrollIntent ?? ListScrollIntent(kind: .top),
                    onSelect: onSelect,
                    onToggle: { session.toggle(items[$0]) },
                    onActions: { index in
                        onSelect(index)
                        onOpenActions()
                    }
                )
            }
        }
    }
}
