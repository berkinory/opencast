import AppKit
import SwiftUI

struct ExtensionSessionView: View {
    static let gridColumns = 5

    let command: ExtensionCommand
    @ObservedObject var host: ExtensionHostManager
    let snapshot: ExtensionRenderSnapshot?
    let errorMessage: String?
    let items: [ExtensionRenderItem]
    let selection: Int
    let scrollIntent: ListScrollIntent?
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    @State private var formValues: [String: String] = [:]
    @State private var formErrors: [String: String] = [:]

    var body: some View {
        Group {
            if let snapshot {
                switch snapshot.root {
                case "detail":
                    detail(snapshot)
                case "form":
                    form(snapshot)
                case "grid":
                    grid(snapshot)
                default:
                    list(snapshot)
                }
            } else if let errorMessage {
                EmptyResults(text: errorMessage)
            } else {
                EmptyResults(text: "Loading \(command.title)…")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay(alignment: .top) {
            if let feedback = host.feedback, feedback.kind == "toast",
                let message = feedback.message
            {
                FeedbackToastView(
                    title: feedback.title,
                    message: message,
                    tone: FeedbackToastTone(style: feedback.style),
                    compact: true
                )
                .padding(.top, Theme.Spacing.sm)
            }
        }
        .overlay(alignment: .topTrailing) {
            if snapshot?.loading == true {
                ProgressView()
                    .controlSize(.small)
                    .padding(Theme.Spacing.sm)
            }
        }
    }

    private func grid(_ snapshot: ExtensionRenderSnapshot) -> some View {
        if items.isEmpty {
            return AnyView(EmptyResults(text: snapshot.emptyView?.title ?? "No extension items found"))
        }
        return AnyView(
            PaletteGridLayout(
                sections: [PaletteGridSection(id: "extension-grid", title: nil, items: items)],
                columns: Self.gridColumns,
                selection: selection,
                scroll: scrollIntent ?? ListScrollIntent(kind: .top),
                columnSpacing: Theme.Spacing.md,
                rowSpacing: Theme.Spacing.md,
                minimumCellHeight: 92,
                contentInsets: EdgeInsets(
                    top: Theme.Spacing.md,
                    leading: Theme.Spacing.md,
                    bottom: Theme.Spacing.md,
                    trailing: Theme.Spacing.md
                ),
                onSelect: onSelect,
                onActivate: onActivate,
                onActions: onActions
            ) { item, selected, hovered in
                ExtensionGridItem(item: item, selected: selected, hovered: hovered)
            } footer: {
                if let pagination = snapshot.pagination, pagination.hasMore {
                    Button("Load More") { host.loadMore(root: "grid") }
                        .buttonStyle(.bordered)
                        .padding(.bottom, Theme.Spacing.md)
                }
            }
        )
    }

    private func list(_ snapshot: ExtensionRenderSnapshot) -> some View {
        if items.isEmpty {
            return AnyView(EmptyResults(text: snapshot.emptyView?.title ?? "No extension items found"))
        }
        return AnyView(
            PaletteListLayout(
                scroll: scrollIntent ?? ListScrollIntent(kind: .top),
                scrollTarget: items.indices.contains(selection) ? items[selection].id : nil
            ) {
                LazyVStack(spacing: 0) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        ExtensionItemRow(item: item, selected: index == selection)
                            .id(item.id)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                onSelect(index)
                            }
                            .simultaneousGesture(
                                TapGesture(count: 2).onEnded {
                                    onSelect(index)
                                    onActivate(index)
                                }
                            )
                            .onRightClick { onActions(index) }
                    }
                }
                .padding(.horizontal, Theme.Spacing.md)
                .padding(.top, Theme.Spacing.xs)
                .padding(.bottom, Theme.Spacing.md)
                if let pagination = snapshot.pagination, pagination.hasMore {
                    Button("Load More") { host.loadMore(root: "list") }
                        .buttonStyle(.bordered)
                        .padding(.bottom, Theme.Spacing.md)
                }
            }
        )
    }

    private func detail(_ snapshot: ExtensionRenderSnapshot) -> some View {
        PaletteActionLayout(title: command.title, subtitle: command.subtitle) {
            ScrollView {
                VStack(alignment: .leading, spacing: Theme.Spacing.xl) {
                    let markdown =
                        snapshot.detail?.markdown.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !markdown.isEmpty {
                        Text(detailMarkdown(markdown))
                            .font(Theme.Typography.body)
                            .foregroundStyle(Theme.Colors.textPrimary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .textSelection(.enabled)
                    }
                    if let detail = snapshot.detail {
                        detailMetadata(detail.metadata)
                        ForEach(detail.sections) { section in
                            VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
                                if !section.title.isEmpty {
                                    Text(section.title)
                                        .font(Theme.Typography.calloutMedium)
                                        .foregroundStyle(Theme.Colors.textPrimary)
                                }
                                detailMetadata(section.metadata)
                            }
                        }
                        ForEach(detail.links) { link in
                            Button(link.title) {
                                guard let url = URL(string: link.url) else { return }
                                NSWorkspace.shared.open(url)
                            }
                            .buttonStyle(.link)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, Theme.Spacing.md)
            }
        } footer: {
            ExtensionActionStrip(actions: snapshot.actions, host: host)
        }
    }

    private func detailMarkdown(_ markdown: String) -> AttributedString {
        (try? AttributedString(markdown: markdown)) ?? AttributedString(markdown)
    }

    private func detailMetadata(_ metadata: [ExtensionRenderMetadata]) -> some View {
        Group {
            if !metadata.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], alignment: .leading) {
                    ForEach(metadata) { entry in
                        HStack(alignment: .top, spacing: Theme.Spacing.sm) {
                            Image(systemName: metadataIcon(for: entry.label))
                                .font(Theme.Typography.iconSmall)
                                .foregroundStyle(Theme.Colors.systemAccent)
                                .frame(width: 20, height: 20)
                            VStack(alignment: .leading, spacing: Theme.Spacing.xxs) {
                                Text(entry.label)
                                    .font(Theme.Typography.caption)
                                    .foregroundStyle(Theme.Colors.textSecondary)
                                Text(entry.value)
                                    .font(Theme.Typography.calloutMedium)
                                    .foregroundStyle(
                                        entry.kind == "tag" ? Theme.Colors.systemAccent : Theme.Colors.textPrimary
                                    )
                                    .lineLimit(2)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(Theme.Spacing.md)
                        .background(
                            Theme.Colors.cardFill,
                            in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
                    }
                }
            }
        }
    }

    private func metadataIcon(for label: String) -> String {
        switch label.lowercased() {
        case "cpu": return "cpu"
        case "memory": return "memorychip"
        case "disk": return "internaldrive"
        case "network in": return "arrow.down.circle"
        case "network out": return "arrow.up.circle"
        case "battery": return "battery.100"
        case "temperature": return "thermometer.medium"
        default: return "chart.bar"
        }
    }

    private func form(_ snapshot: ExtensionRenderSnapshot) -> some View {
        PaletteActionLayout(title: command.title, subtitle: command.subtitle) {
            VStack(alignment: .leading, spacing: Theme.Spacing.lg) {
                ForEach(snapshot.fields) { field in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        Text(field.title)
                            .font(Theme.Typography.calloutMedium)
                            .foregroundStyle(Theme.Colors.textPrimary)
                        fieldInput(field)
                        if let error = formErrors[field.id] ?? field.error {
                            Text(error)
                                .font(Theme.Typography.caption)
                                .foregroundStyle(Theme.Colors.destructive)
                        }
                    }
                }
            }
        } footer: {
            ExtensionActionStrip(
                actions: snapshot.actions,
                host: host,
                fields: formValues,
                requiredFields: snapshot.fields,
                onValidationFailure: { errors in formErrors = errors }
            )
        }
        .onAppear {
            formValues = Dictionary(uniqueKeysWithValues: snapshot.fields.map { ($0.id, $0.value ?? "") })
        }
    }

    @ViewBuilder
    private func fieldInput(_ field: ExtensionRenderField) -> some View {
        switch field.kind {
        case "checkbox":
            Toggle(
                field.title,
                isOn: Binding(
                    get: { (formValues[field.id] ?? field.value ?? "false") == "true" },
                    set: { setField(field, value: $0 ? "true" : "false") }
                )
            )
            .toggleStyle(.switch)
        case "dropdown":
            Picker(field.title, selection: binding(for: field)) {
                ForEach(field.options, id: \.value) { option in
                    Text(option.title).tag(option.value)
                }
            }
            .pickerStyle(.menu)
        case "date":
            DatePicker(field.title, selection: dateBinding(for: field), displayedComponents: [.date])
        case "password":
            SecureField(field.placeholder ?? field.title, text: binding(for: field))
                .textFieldStyle(.roundedBorder)
        case "textarea":
            TextEditor(text: binding(for: field))
                .frame(minHeight: 80)
                .padding(Theme.Spacing.xs)
                .background(Theme.Colors.rowHover, in: RoundedRectangle(cornerRadius: Theme.Radius.row))
        case "file", "directory":
            Button(formValues[field.id] ?? field.placeholder ?? "Choose (field.kind)") {
                let panel = NSOpenPanel()
                panel.canChooseFiles = field.kind == "file"
                panel.canChooseDirectories = field.kind == "directory"
                guard panel.runModal() == .OK, let url = panel.url else { return }
                setField(field, value: url.path)
            }
            .buttonStyle(.bordered)
        default:
            TextField(field.placeholder ?? field.title, text: binding(for: field))
                .textFieldStyle(.roundedBorder)
        }
    }

    private func binding(for field: ExtensionRenderField) -> Binding<String> {
        Binding(
            get: { formValues[field.id] ?? field.value ?? "" },
            set: { setField(field, value: $0) }
        )
    }

    private func setField(_ field: ExtensionRenderField, value: String) {
        formValues[field.id] = value
        host.changeField(id: field.id, value: value)
    }

    private func dateBinding(for field: ExtensionRenderField) -> Binding<Date> {
        Binding(
            get: {
                ISO8601DateFormatter().date(from: formValues[field.id] ?? field.value ?? "") ?? Date()
            },
            set: { setField(field, value: ISO8601DateFormatter().string(from: $0)) }
        )
    }
}

private struct ExtensionActionStrip: View {
    let actions: [ExtensionRenderAction]
    let host: ExtensionHostManager
    let fields: [String: String]?
    let requiredFields: [ExtensionRenderField]
    let onValidationFailure: ([String: String]) -> Void

    init(
        actions: [ExtensionRenderAction], host: ExtensionHostManager, fields: [String: String]? = nil,
        requiredFields: [ExtensionRenderField] = [],
        onValidationFailure: @escaping ([String: String]) -> Void = { _ in }
    ) {
        self.actions = actions
        self.host = host
        self.fields = fields
        self.requiredFields = requiredFields
        self.onValidationFailure = onValidationFailure
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            ForEach(actionGroups, id: \.title) { group in
                VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                    if !group.title.isEmpty {
                        Text(group.title)
                            .font(Theme.Typography.caption)
                            .foregroundStyle(Theme.Colors.textSecondary)
                    }
                    HStack(spacing: Theme.Spacing.sm) {
                        ForEach(group.actions) { action in
                            Button(action.title) { invoke(action) }
                                .buttonStyle(.borderedProminent)
                                .tint(action.destructive ? Theme.Colors.destructive : Theme.Colors.systemAccent)
                        }
                    }
                }
            }
            if let progress = host.actionProgress {
                HStack(spacing: Theme.Spacing.sm) {
                    ProgressView()
                    Text(progress.chunk ?? "Working…")
                        .font(Theme.Typography.caption)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
            }
        }
    }

    private var actionGroups: [(title: String, actions: [ExtensionRenderAction])] {
        var groups: [(String, [ExtensionRenderAction])] = []
        for action in actions {
            let title = action.section ?? ""
            if let index = groups.firstIndex(where: { $0.0 == title }) {
                groups[index].1.append(action)
            } else {
                groups.append((title, [action]))
            }
        }
        return groups.map { (title: $0.0, actions: $0.1) }
    }

    private func invoke(_ action: ExtensionRenderAction) {
        guard validateFields() else { return }
        if action.requiresConfirmation,
            !AppCore.shared.confirmExtensionAction(
                message: action.title,
                informativeText: "This extension action will run now.",
                confirmTitle: action.title
            )
        {
            return
        }
        host.invoke(actionID: action.id, itemID: nil, fields: fields)
    }

    private func validateFields() -> Bool {
        guard let fields else { return true }
        let errors: [String: String] = Dictionary(
            uniqueKeysWithValues: requiredFields.compactMap { field in
                guard field.required,
                    (fields[field.id] ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                else {
                    return nil
                }
                return (field.id, "This field is required.")
            })
        onValidationFailure(errors)
        return errors.isEmpty
    }
}

private struct ExtensionGridItem: View {
    let item: ExtensionRenderItem
    let selected: Bool
    let hovered: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: Theme.Spacing.sm) {
            FeatureIcon(
                systemImage: item.icon ?? "puzzlepiece.extension", tint: Theme.Colors.systemAccent, size: 32
            )
            Text(item.title)
                .font(Theme.Typography.calloutMedium)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(2)
            if let subtitle = item.subtitle {
                Text(subtitle)
                    .font(Theme.Typography.caption)
                    .foregroundStyle(Theme.Colors.textSecondary)
                    .lineLimit(2)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 92, alignment: .topLeading)
        .padding(Theme.Spacing.lg)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(
                    selected
                        ? Theme.Colors.selection
                        : hovered ? Theme.Colors.rowHover : Theme.Colors.cardFill)
        )
    }
}

private struct ExtensionItemRow: View {
    let item: ExtensionRenderItem
    let selected: Bool
    @State private var loadedIcon: NSImage?

    private var processID: pid_t? {
        guard let icon = item.icon, icon.hasPrefix("process:"),
            let value = Int32(
                String(icon.dropFirst("process:".count).split(separator: "|", maxSplits: 1)[0]))
        else { return nil }
        return value
    }

    private var processExecutablePath: String? {
        guard let icon = item.icon, icon.hasPrefix("process:"),
            let path = icon.split(separator: "|", maxSplits: 1).dropFirst().first,
            !path.isEmpty
        else { return nil }
        return String(path)
    }

    private var iconPath: String? {
        guard let icon = item.icon, icon.hasPrefix("/") else { return nil }
        return icon
    }

    var body: some View {
        PaletteRow(
            selected: selected,
            leading: {
                if let loadedIcon {
                    Image(nsImage: loadedIcon).resizable()
                } else if let icon = item.icon, iconPath == nil {
                    FeatureIcon(systemImage: icon, tint: Theme.Colors.systemAccent, size: Theme.Size.rowIcon)
                } else {
                    FeatureIcon(
                        systemImage: processID == nil ? "puzzlepiece.extension" : "gearshape.2",
                        tint: Theme.Colors.systemAccent,
                        size: Theme.Size.rowIcon
                    )
                }
            },
            content: {
                Text(item.title)
                    .font(Theme.Typography.rowTitle)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .layoutPriority(1)
            },
            trailing: {
                if let subtitle = item.subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.rowTrailing)
                        .foregroundStyle(Theme.Colors.textSecondary)
                        .lineLimit(1)
                }
                ForEach(item.accessories) { accessory in
                    HStack(spacing: Theme.Spacing.xs) {
                        if let icon = accessory.icon {
                            Image(systemName: icon)
                                .font(Theme.Typography.iconSmall)
                                .foregroundStyle(Theme.Colors.rowKind)
                        }
                        if let text = accessory.text {
                            Text(text)
                                .font(Theme.Typography.rowTrailing)
                                .foregroundStyle(Theme.Colors.rowKind)
                                .lineLimit(1)
                        }
                    }
                }
            }
        )
        .task(id: item.icon) {
            loadedIcon = nil
            if let processID {
                loadedIcon = NSRunningApplication(processIdentifier: processID)?.icon
                if loadedIcon == nil, let processExecutablePath {
                    loadedIcon = await IconCache.loadAsync(forFile: processExecutablePath)
                }
                return
            }
            guard let iconPath else { return }
            loadedIcon = await IconCache.loadAsync(forFile: iconPath)
        }
    }
}

struct ExtensionSortButton: View {
    let dropdown: ExtensionListDropdown
    let action: () -> Void
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.sm) {
                Image(systemName: "arrow.up.arrow.down").symbolRenderingMode(.hierarchical)
                Text(
                    dropdown.options.first(where: { $0.value == dropdown.value })?.title ?? dropdown.tooltip)
                Image(systemName: "chevron.down").font(Theme.Typography.keyCap)
            }
            .font(Theme.Typography.bar)
            .foregroundStyle(Theme.Colors.textSecondary)
            .padding(.horizontal, Theme.Spacing.md)
            .frame(height: 28)
            .contentShape(Capsule())
            .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
        .fixedSize()
    }
}

@MainActor
enum ExtensionActionsMenu {
    static func content(
        item: ExtensionRenderItem, host: ExtensionHostManager
    ) -> PopoverMenuContent? {
        guard !item.actions.isEmpty else { return nil }
        return PopoverMenuContent(
            header: item.title,
            items: item.actions.map { action in
                PopoverMenuItem(
                    title: action.title,
                    systemImage: actionIcon(for: action),
                    shortcut: action.shortcut,
                    isDestructive: action.destructive
                ) {
                    if action.requiresConfirmation,
                        !AppCore.shared.confirmExtensionAction(
                            message: action.title,
                            informativeText: "This extension action will run now.",
                            confirmTitle: action.title
                        )
                    {
                        return
                    }
                    host.invoke(actionID: action.id, itemID: item.id)
                }
            }
        )
    }

    private static func actionIcon(for action: ExtensionRenderAction) -> String {
        switch action.title.lowercased() {
        case "kill": return "stop.circle"
        case "force kill": return "xmark.octagon"
        case "restart": return "arrow.clockwise"
        case "force restart": return "arrow.clockwise.circle.fill"
        default: return action.destructive ? "trash" : "bolt"
        }
    }
}
