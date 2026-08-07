import AppKit
import SwiftUI

struct QuicklinkDraft: Equatable {
    var name: String
    var link: String
    var icon: String
    var openWithBundleID: String
}

struct QuicklinkEditorView: View {
    let quicklink: Quicklink?
    let onSave: (QuicklinkDraft) -> String?

    @State private var name: String
    @State private var link: String
    @State private var icon: String
    @State private var openWithBundleID: String
    @State private var validationMessage: String?
    @EnvironmentObject private var core: AppCore
    @EnvironmentObject private var palette: PaletteViewModel

    private var isEditing: Bool { quicklink != nil }

    init(quicklink: Quicklink?, onSave: @escaping (QuicklinkDraft) -> String?) {
        self.quicklink = quicklink
        self.onSave = onSave
        _name = State(initialValue: quicklink?.name ?? "")
        _link = State(initialValue: quicklink?.link ?? "")
        _icon = State(initialValue: quicklink?.icon ?? "link")
        _openWithBundleID = State(
            initialValue: quicklink?.openWithBundleID ?? Self.defaultBrowserBundleID
        )
    }

    var body: some View {
        PaletteActionLayout(
            title: isEditing ? "Edit Quicklink" : "Create Quicklink",
            subtitle: "Open a URL, file, or folder faster."
        ) {
            HStack(alignment: .top, spacing: Theme.Spacing.xxl) {
                linkEditor
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
                        title: isEditing ? "Edit Quicklink" : "Create Quicklink",
                        systemImage: "link",
                        tint: Theme.Colors.systemAccent
                    )
                }
                Spacer(minLength: 0)
                PaletteActionGroup(
                    primaryTitle: isEditing ? "Save Changes" : "Save Quicklink",
                    primaryShortcut: ["⌘", "↵"],
                    primaryAction: save
                )
            }
        }
        .onAppear {
            palette.onCommandEnter = {
                save()
                return true
            }
        }
        .onDisappear { palette.onCommandEnter = nil }
        .onKeyPress(keys: [.return], phases: .down) { press in
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

    private var linkEditor: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Link")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            ZStack(alignment: .topLeading) {
                TextEditor(text: $link)
                    .font(Theme.Typography.monospacedSubheadline)
                    .paletteTextInputCursor()
                    .scrollContentBackground(.hidden)
                    .padding(Theme.Spacing.md)
                    .padding(.bottom, Theme.Spacing.xxl)

                VStack {
                    Spacer()
                    HStack {
                        Spacer()
                        Button(action: chooseFileOrFolder) {
                            Image(systemName: "folder")
                                .font(Theme.Typography.iconMedium)
                                .foregroundStyle(Theme.Colors.textSecondary)
                                .frame(width: 28, height: 28)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .settingsFocusRing(cornerRadius: Theme.Radius.menu)
                        .help("Choose a file or folder")
                        .padding(.trailing, Theme.Spacing.sm)
                        .padding(.bottom, Theme.Spacing.sm)
                    }
                }
            }
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
            QuicklinkNameField(text: $name, icon: $icon)
            QuicklinkOpenWithField(bundleID: $openWithBundleID)
            Spacer(minLength: 0)
        }
    }

    private func save() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedLink = link.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else {
            validationMessage = QuicklinkValidationError.emptyName.localizedDescription
            return
        }
        guard !trimmedLink.isEmpty else {
            validationMessage = QuicklinkValidationError.emptyLink.localizedDescription
            return
        }
        guard !openWithBundleID.isEmpty else {
            validationMessage = QuicklinkValidationError.missingApplication.localizedDescription
            return
        }
        validationMessage = onSave(
            QuicklinkDraft(
                name: trimmedName,
                link: trimmedLink,
                icon: icon,
                openWithBundleID: openWithBundleID
            )
        )
    }

    private func chooseFileOrFolder() {
        core.quicklinks.chooseTarget { path in
            link = path
        }
    }

    private static var defaultBrowserBundleID: String {
        guard let url = URL(string: "https://example.com"),
            let applicationURL = NSWorkspace.shared.urlForApplication(toOpen: url),
            let bundleID = Bundle(url: applicationURL)?.bundleIdentifier
        else { return "com.apple.Safari" }
        return bundleID
    }
}

private struct QuicklinkNameField: View {
    @Binding var text: String
    @Binding var icon: String

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Name & Icon")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            HStack(spacing: 0) {
                TextField("Quicklink name", text: $text)
                    .textFieldStyle(.plain)
                    .font(Theme.Typography.callout)
                    .padding(.leading, Theme.Spacing.md)
                    .paletteTextInputCursor()
                Divider()
                    .frame(height: 20)
                    .overlay(Theme.Colors.cardStroke)
                Menu {
                    ForEach(QuicklinkIcon.names, id: \.self) { name in
                        Button {
                            icon = name
                        } label: {
                            Image(systemName: name)
                        }
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

private struct QuicklinkOpenWithField: View {
    @Binding var bundleID: String
    @EnvironmentObject private var appIndex: AppIndex
    @State private var showingPicker = false

    private var selectedApp: AppEntry? {
        appIndex.apps.first { $0.kind == .application && $0.bundleID == bundleID }
    }

    private var selectedName: String {
        selectedApp?.name ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { $0.deletingPathExtension().lastPathComponent }
            ?? bundleID
    }

    private var selectedIcon: NSImage {
        selectedApp?.icon
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
            ?? NSApp.applicationIconImage
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Open With")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(Theme.Colors.textSecondary)
            Button {
                showingPicker = true
            } label: {
                HStack(spacing: Theme.Spacing.md) {
                    Image(nsImage: selectedIcon)
                        .resizable()
                        .interpolation(.high)
                        .frame(width: 22, height: 22)
                    Text(selectedName)
                        .font(Theme.Typography.callout)
                        .lineLimit(1)
                    Spacer(minLength: 0)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 9, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 32)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .strokeBorder(Theme.Colors.cardStroke, lineWidth: 1)
            )
            .popover(isPresented: $showingPicker, arrowEdge: .bottom) {
                QuicklinkAppPicker(selectedBundleID: bundleID) { id in
                    bundleID = id
                    showingPicker = false
                }
                .environmentObject(appIndex)
            }
        }
    }
}

private struct QuicklinkAppPicker: View {
    let selectedBundleID: String
    let onSelect: (String) -> Void

    @EnvironmentObject private var appIndex: AppIndex
    @State private var query = ""
    @FocusState private var queryFocused: Bool

    private var candidates: [AppEntry] {
        (query.isEmpty ? appIndex.apps : appIndex.matches(query))
            .filter { $0.kind == .application && $0.bundleID != nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                TextField("Search applications", text: $query)
                    .textFieldStyle(.plain)
                    .focused($queryFocused)
            }
            .padding(Theme.Spacing.lg)

            Rectangle()
                .fill(Theme.Settings.Colors.rowDivider)
                .frame(height: 1)

            ScrollView {
                LazyVStack(spacing: Theme.Spacing.xxs) {
                    ForEach(candidates) { app in
                        Button {
                            if let id = app.bundleID { onSelect(id) }
                        } label: {
                            HStack(spacing: Theme.Spacing.lg) {
                                Image(nsImage: app.icon)
                                    .resizable()
                                    .frame(width: 22, height: 22)
                                Text(app.name)
                                    .lineLimit(1)
                                Spacer(minLength: 0)
                                if app.bundleID == selectedBundleID {
                                    Image(systemName: "checkmark")
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.horizontal, Theme.Spacing.md)
                            .padding(.vertical, Theme.Spacing.sm)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(Theme.Spacing.sm)
                .frame(maxWidth: .infinity)
            }
            .overlay {
                if candidates.isEmpty {
                    Text("No matching applications.")
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .overlayScroller(disablesElasticity: true)
        }
        .frame(width: 280, height: 320)
        .onAppear { queryFocused = true }
    }
}

enum QuicklinkIcon {
    static let names = [
        "link", "globe", "safari", "folder", "doc", "terminal", "calendar",
        "music.note", "play.rectangle", "star", "heart", "house",
    ]
}

struct QuicklinkSearchView: View {
    let results: [Quicklink]
    let selectedID: Quicklink.ID?
    let scrollIntent: ListScrollIntent?
    let onSelect: (Quicklink) -> Void
    let onActivate: (Quicklink) -> Void
    let onActions: (Quicklink) -> Void

    var body: some View {
        if results.isEmpty {
            EmptyResults(text: "No quicklinks found")
        } else {
            let selected = results.first { $0.id == selectedID }
            PaletteDetailLayout(
                listWidth: Theme.Size.clipboardListWidth,
                detailTitle: selected?.name ?? "Preview",
                sidebar: {
                    QuicklinkList(
                        results: results,
                        selectedID: selectedID,
                        scrollIntent: scrollIntent,
                        onSelect: onSelect,
                        onActivate: onActivate,
                        onActions: onActions
                    )
                },
                detail: {
                    QuicklinkPreview(quicklink: selected)
                },
                metadata: {
                    if let selected {
                        QuicklinkMetadata(quicklink: selected)
                    }
                }
            )
        }
    }
}

private struct QuicklinkList: View {
    let results: [Quicklink]
    let selectedID: Quicklink.ID?
    let scrollIntent: ListScrollIntent?
    let onSelect: (Quicklink) -> Void
    let onActivate: (Quicklink) -> Void
    let onActions: (Quicklink) -> Void

    private enum Row: Identifiable {
        case header(String)
        case quicklink(Quicklink)

        var id: String {
            switch self {
            case .header(let title): return "header-\(title)"
            case .quicklink(let quicklink): return quicklink.id.uuidString
            }
        }
    }

    private var rows: [Row] {
        var rows: [Row] = []
        var currentTitle: String?
        for quicklink in results {
            let title = quicklink.isPinned ? "Pinned" : DateBucket(for: quicklink.modifiedAt).title
            if title != currentTitle {
                rows.append(.header(title))
                currentTitle = title
            }
            rows.append(.quicklink(quicklink))
        }
        return rows
    }

    var body: some View {
        let rows = rows
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(rows) { row in
                        switch row {
                        case .header(let title):
                            SectionHeader(title: title, isFirst: row.id == rows.first?.id)
                        case .quicklink(let quicklink):
                            QuicklinkRow(quicklink: quicklink, selected: quicklink.id == selectedID)
                                .contentShape(Rectangle())
                                .onTapGesture { onSelect(quicklink) }
                                .simultaneousGesture(
                                    TapGesture(count: 2).onEnded {
                                        onSelect(quicklink)
                                        onActivate(quicklink)
                                    }
                                )
                                .onRightClick { onActions(quicklink) }
                                .id(quicklink.id)
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

struct QuicklinkRow: View {
    let quicklink: Quicklink
    let selected: Bool

    var body: some View {
        PaletteRow(
            selected: selected,
            leading: {
                FeatureIcon(systemImage: quicklink.icon, tint: Theme.Colors.systemAccent)
            },
            content: {
                Text(quicklink.name)
                    .font(Theme.Typography.rowTitle)
                    .lineLimit(1)
            },
            trailing: {
                Text("Quicklink")
                    .font(Theme.Typography.rowTrailing)
                    .foregroundStyle(Theme.Colors.rowKind)
            }
        )
    }
}

private struct QuicklinkPreview: View {
    let quicklink: Quicklink?

    var body: some View {
        if let quicklink {
            ScrollView {
                Text(quicklink.link)
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

private struct QuicklinkMetadata: View {
    let quicklink: Quicklink

    private var applicationURL: URL? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: quicklink.openWithBundleID)
    }

    private var applicationName: String {
        applicationURL
            .map { $0.deletingPathExtension().lastPathComponent }
            ?? quicklink.openWithBundleID
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            Text("Information")
                .font(Theme.Typography.sectionHeader)
                .foregroundStyle(.secondary)
            VStack(spacing: 0) {
                row("Name", quicklink.name)
                Divider()
                row("Open With", applicationName, icon: applicationURL.map { IconCache.icon(forFile: $0.path) })
                Divider()
                row("Created", Self.dateFormatter.string(from: quicklink.createdAt))
                Divider()
                row("Modified", Self.dateFormatter.string(from: quicklink.modifiedAt))
            }
        }
        .padding(.top, Theme.Spacing.xl)
    }

    private func row(_ label: String, _ value: String, icon: NSImage? = nil) -> some View {
        HStack(spacing: Theme.Spacing.sm) {
            Text(label).foregroundStyle(.secondary)
            Spacer(minLength: Theme.Spacing.lg)
            if let icon {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: Theme.Size.menuIcon, height: Theme.Size.menuIcon)
            }
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
