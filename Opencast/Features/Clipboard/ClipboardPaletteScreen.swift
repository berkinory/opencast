import SwiftUI

struct ClipFollowKey: Equatable {
    let id: ClipboardItem.ID?
    let token: UUID
}

@MainActor
struct ClipboardPaletteScreen: PaletteScreen {
    let items: [ClipboardItem]
    let selection: Int
    let scrollIntent: ListScrollIntent?
    let store: ClipboardStore
    let coordinator: ClipboardCoordinator
    let filter: ClipboardFilter
    let pasteTarget: PasteTarget?
    let followKey: ClipFollowKey
    let isQueryEmpty: Bool
    let onSelect: (Int) -> Void
    let onFollow: (Int?) -> Void
    let onOpenActions: () -> Void
    let onFeedback: (String) -> Void
    let onFilterChange: (ClipboardFilter) -> Void

    var selectedItem: ClipboardItem? {
        items.indices.contains(selection) ? items[selection] : nil
    }

    var itemCount: Int { items.count }

    var actionsContent: PopoverMenuContent? {
        guard let selectedItem else { return nil }
        return ClipboardActionsMenu.content(
            item: selectedItem,
            coordinator: coordinator,
            target: pasteTarget,
            onFeedback: onFeedback
        )
    }

    var body: some View {
        Group {
            if items.isEmpty {
                EmptyResults(
                    text: filter == .all
                        ? "Clipboard history is empty"
                        : "No \(filter.title.lowercased()) entries"
                )
            } else {
                PaletteDetailLayout(
                    listWidth: Theme.Size.clipboardListWidth,
                    detailTitle: "Preview",
                    sidebar: {
                        VStack(spacing: 0) {
                            HStack {
                                Text("History")
                                    .font(Theme.Typography.sectionHeader)
                                    .foregroundStyle(.secondary)
                                Spacer()
                                ClipboardFilterMenu(filter: filter, onChange: onFilterChange)
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.top, Theme.Spacing.md)
                            .padding(.bottom, Theme.Spacing.xs)

                            ClipboardList(
                                results: items,
                                selectedID: selectedItem?.id,
                                scrollIntent: scrollIntent,
                                onSelect: select,
                                onActivate: activate,
                                onActions: openActions
                            )
                        }
                    },
                    detail: {
                        ClipboardPreview(item: selectedItem)
                    },
                    metadata: {
                        if let selectedItem {
                            ClipboardMetadata(
                                item: selectedItem,
                                imageURL: store.imageURL(for: selectedItem)
                            )
                        }
                    }
                )
            }
        }
        .onChange(of: followKey) { old, new in
            guard old.id != nil else { return }
            let movedIndex =
                isQueryEmpty && old.id != new.id
                ? new.id.flatMap { id in items.firstIndex(where: { $0.id == id }) }
                : nil
            onFollow(movedIndex)
        }
    }

    @discardableResult
    func activate() -> Bool {
        guard let selectedItem else { return false }
        coordinator.paste(selectedItem)
        return true
    }

    @discardableResult
    func copy() -> Bool {
        guard let selectedItem else { return false }
        coordinator.copy(selectedItem)
        return true
    }

    @discardableResult
    func delete() -> Bool {
        guard let selectedItem else { return false }
        coordinator.delete(selectedItem)
        onFeedback("Deleted entry")
        return true
    }

    @discardableResult
    func togglePinned() -> Bool {
        guard let selectedItem else { return false }
        coordinator.togglePinned(selectedItem)
        return true
    }

    private func select(_ item: ClipboardItem) {
        onSelect(items.firstIndex(of: item) ?? 0)
    }

    private func activate(_ item: ClipboardItem) {
        select(item)
        coordinator.paste(item)
    }

    private func openActions(_ item: ClipboardItem) {
        guard let index = items.firstIndex(of: item) else { return }
        onSelect(index)
        onOpenActions()
    }
}

private struct ClipboardFilterMenu: View {
    let filter: ClipboardFilter
    let onChange: (ClipboardFilter) -> Void

    var body: some View {
        Menu {
            ForEach(ClipboardFilter.allCases) { option in
                Button {
                    onChange(option)
                } label: {
                    Label(option.title, systemImage: option.systemImage)
                    if option == filter { Image(systemName: "checkmark") }
                }
            }
        } label: {
            Label(filter.title, systemImage: filter.systemImage)
                .font(Theme.Typography.callout)
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
    }
}
