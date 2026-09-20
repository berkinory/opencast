import SwiftUI

struct SnippetDraft: Equatable {
    var name: String
    var content: String
    var keyword: String
    var icon: String
}

struct SnippetEditorView: View {
    let snippet: Snippet?
    let onSave: (SnippetDraft) -> String?

    @State private var name: String
    @State private var content: String
    @State private var keyword: String
    @State private var icon: String
    @State private var validationMessage: String?
    @FocusState private var contentFocused: Bool
    @EnvironmentObject private var palette: PaletteViewModel

    private var isEditing: Bool { snippet != nil }

    init(snippet: Snippet?, onSave: @escaping (SnippetDraft) -> String?) {
        self.snippet = snippet
        self.onSave = onSave
        _name = State(initialValue: snippet?.name ?? "")
        _content = State(initialValue: snippet?.content ?? "")
        _keyword = State(initialValue: snippet?.keyword ?? "")
        _icon = State(initialValue: snippet?.icon ?? "doc.text")
    }

    var body: some View {
        PaletteActionLayout(
            title: isEditing ? "Edit Snippet" : "Create Snippet",
            subtitle: "Save text you use often and paste it anywhere."
        ) {
            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                contentEditor
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                details
                    .frame(width: 250)
            }
        } footer: {
            HStack(spacing: Theme.Spacing.md) {
                if let validationMessage {
                    PaletteFeedbackButton(message: validationMessage, tone: .error)
                } else {
                    PaletteContextPill(
                        title: isEditing ? "Edit Snippet" : "Create Snippet",
                        systemImage: "text.quote",
                        tint: Theme.Colors.systemAccent
                    )
                }
                Spacer(minLength: 0)
                PaletteActionGroup(
                    primaryTitle: isEditing ? "Save Changes" : "Save Snippet",
                    primaryShortcut: ["⌘", "↵"],
                    primaryAction: save
                )
            }
        }
        .onAppear {
            contentFocused = true
            palette.onCommandEnter = {
                save()
                return true
            }
        }
        .onDisappear { palette.onCommandEnter = nil }
        .onKeyPress(keys: [.return, KeyEquivalent("\u{3}")], phases: .down) { press in
            guard press.modifiers.contains(.command) else { return .ignored }
            save()
            return .handled
        }
        .task(id: validationMessage) {
            guard validationMessage != nil else { return }
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled else { return }
            validationMessage = nil
        }
    }

    private var contentEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Snippet Text")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextEditor(text: $content)
                .font(Theme.Typography.monospacedSubheadline)
                .paletteTextInputCursor()
                .scrollContentBackground(.hidden)
                .focused($contentFocused)
                .padding(Theme.Spacing.md)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .fill(Theme.Colors.cardFill)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                        .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
                )
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
            SnippetNameField(text: $name, icon: $icon)
            SnippetField(title: "Keyword", prompt: "Optional keyword", text: $keyword)
            Spacer(minLength: 0)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = "Add a name for the snippet."
            return
        }
        guard !content.isEmpty else {
            validationMessage = "Add some text to the snippet."
            return
        }
        validationMessage = onSave(
            SnippetDraft(name: trimmedName, content: content, keyword: keyword, icon: icon)
        )
    }
}

private struct SnippetNameField: View {
    @Binding var text: String
    @Binding var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Name & Icon")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 0) {
                TextField("Snippet name", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.callout)
                    .padding(.leading, Theme.Spacing.md)
                    .paletteTextInputCursor()
                Divider()
                    .frame(height: 20)
                    .overlay(Theme.Colors.cardStroke)
                Menu {
                    ForEach(SnippetIcon.names, id: \.self) { name in
                        Button {
                            icon = name
                        } label: {
                            Image(systemName: name)
                        }
                        .help(name)
                    }
                } label: {
                    HStack(spacing: Theme.Spacing.sm) {
                        Image(systemName: icon)
                            .font(Theme.Typography.iconMedium)
                            .frame(width: 22, height: 20)
                        Image(systemName: "chevron.down")
                            .font(.system(size: 9, weight: .semibold))
                            .frame(width: 12, height: 20)
                    }
                    .padding(.trailing, Theme.Spacing.xl)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .frame(width: 48, height: 32, alignment: .trailing)
                }
                .menuStyle(.borderlessButton)
                .frame(width: 48, height: 32)
                .onHover { hovering in
                    if hovering { NSCursor.arrow.set() }
                }
            }
            .frame(height: 32)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )
        }
    }
}

private struct SnippetField: View {
    let title: String
    let prompt: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text(title)
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .font(Theme.Typography.callout)
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 32)
                .background(
                    RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                        .fill(Theme.Colors.controlSurface)
                )
                .paletteTextInputCursor()
        }
    }
}

enum SnippetIcon {
    static let names = [
        "doc.text", "text.quote", "envelope", "house", "person", "phone", "link",
        "chevron.left.forwardslash.chevron.right", "terminal", "star", "heart", "calendar",
    ]
}

struct SnippetSearchView: View {
    let results: [Snippet]
    let selectedID: Snippet.ID?
    let scrollIntent: ListScrollIntent?
    let onSelect: (Snippet) -> Void
    let onActivate: (Snippet) -> Void
    let onActions: (Snippet) -> Void

    var body: some View {
        if results.isEmpty {
            EmptyResults(text: "No snippets found")
        } else {
            let selected = results.first { $0.id == selectedID }
            PaletteDetailLayout(
                listWidth: Theme.Size.clipboardListWidth,
                detailTitle: selected?.name ?? "Preview",
                sidebar: {
                    SnippetList(
                        results: results,
                        selectedID: selectedID,
                        scrollIntent: scrollIntent,
                        onSelect: onSelect,
                        onActivate: onActivate,
                        onActions: onActions
                    )
                },
                detail: {
                    SnippetPreview(snippet: selected)
                },
                metadata: {
                    if let selected {
                        SnippetMetadata(snippet: selected)
                    }
                }
            )
        }
    }
}

private struct SnippetList: View {
    let results: [Snippet]
    let selectedID: Snippet.ID?
    let scrollIntent: ListScrollIntent?
    let onSelect: (Snippet) -> Void
    let onActivate: (Snippet) -> Void
    let onActions: (Snippet) -> Void

    private enum Row: Identifiable {
        case header(String)
        case snippet(Snippet)

        var id: String {
            switch self {
            case .header(let title): return "header-\(title)"
            case .snippet(let snippet): return snippet.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var currentTitle: String?
        for snippet in results {
            let title = snippet.isPinned ? "Pinned" : DateBucket(for: snippet.modifiedAt).title
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            rows.append(.snippet(snippet))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .snippet(let snippet):
                            SnippetRow(snippet: snippet, selected: snippet.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(snippet) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(snippet)
                                        onActivate(snippet)
                                    }
                                )
                                .onRightClick { onActions(snippet) }
                                .id(snippet.id)
                        }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                .hideNativeScrollers()
                .resetNativeScrollToTop(id: scrollIntent?.kind == .top ? scrollIntent?.id : nil)
            }
            .edgeDissolve()
            .thinScrollbar()
            .task(id: scrollIntent) {
                guard let scrollIntent, scrollIntent.kind == .follow,
                    let selectedID
                else { return }
                proxy.scrollTo(selectedID)
            }
        }
    }
}

private struct SnippetRow: View {
    let snippet: Snippet
    let selected: Bool

    var body: some View {
        PaletteRow(
            selected: selected,
            leading: {
                FeatureIcon(systemImage: snippet.icon, tint: Theme.Colors.systemAccent)
            },
            content: {
                Text(snippet.name)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
            },
            trailing: {
                if !snippet.keyword.isEmpty {
                    Text(snippet.keyword)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.rowSecondary)
                        .lineLimit(1)
                }
            }
        )
    }
}

private struct SnippetPreview: View {
    let snippet: Snippet?

    var body: some View {
        if let snippet {
            ScrollView {
                Text(snippet.content)
                    .font(Theme.Typography.monospacedSubheadline)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                    .overlayScroller()
            }
        } else {
            Color.clear
        }
    }
}

private struct SnippetMetadata: View {
    let snippet: Snippet

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Information")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                row("Name", snippet.name)
                Divider()
                row("Keyword", snippet.keyword.isEmpty ? "None" : snippet.keyword)
                Divider()
                row("Created", Self.dateFormatter.string(from: snippet.createdAt))
                Divider()
                row("Modified", Self.dateFormatter.string(from: snippet.modifiedAt))
            }
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private func row(_ label: String, _ value: String) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: Theme.Spacing.lg)
            Text(value).lineLimit(1).truncationMode(.middle)
        }
        .font(Theme.Typography.callout)
        .padding(.vertical, Theme.Spacing.sm)
    }

    @MainActor private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .medium
        formatter.doesRelativeDateFormatting = true
        return formatter
    }()
}
