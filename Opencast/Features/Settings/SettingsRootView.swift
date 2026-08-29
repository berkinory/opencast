import AppKit
import SwiftUI

extension Notification.Name {
    /// Navigates an already-open Settings window without rebuilding its SwiftUI tree.
    static let opencastSelectSettingsRoute = Notification.Name("OpencastSelectSettingsRoute")
}

struct SettingsRoute: Hashable, Sendable {
    let tab: SettingsTab
    var destination: SettingsDestination? = nil

    static let general = SettingsRoute(tab: .general)
    static let about = SettingsRoute(tab: .about)
}

enum SettingsTab: Int, CaseIterable, Identifiable, Sendable {
    case general, hyperKey, launcher, commands, clipboard, snippets, quicklinks, emoji, calculator
    case windowManagement, about

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .general: return "General"
        case .hyperKey: return "Hyper Key"
        case .launcher: return "Launcher"
        case .commands: return "Commands"
        case .clipboard: return "Clipboard"
        case .snippets: return "Snippets"
        case .quicklinks: return "Quicklinks"
        case .emoji: return "Emoji"
        case .calculator: return "Calculator"
        case .windowManagement: return "Window"
        case .about: return "About"
        }
    }

    var systemImage: String {
        switch self {
        case .general: return "switch.2"
        case .hyperKey: return "capslock"
        case .launcher: return "command"
        case .commands: return "terminal"
        case .clipboard: return "clipboard"
        case .snippets: return "text.quote"
        case .quicklinks: return "link"
        case .emoji: return "face.smiling"
        case .calculator: return "function"
        case .windowManagement: return "macwindow.and.cursorarrow"
        case .about: return "info.circle"
        }
    }

    var group: SettingsGroup {
        switch self {
        case .general, .hyperKey, .launcher, .commands: return .preferences
        case .clipboard, .snippets, .quicklinks, .emoji, .calculator, .windowManagement:
            return .features
        case .about: return .about
        }
    }

    var tint: Color {
        switch self {
        case .general: return Theme.Colors.systemAccent
        case .hyperKey: return Theme.Colors.systemAccent
        case .launcher: return Theme.Colors.launcherAccent
        case .commands: return Theme.Colors.systemAccent
        case .clipboard: return Theme.Colors.clipboardAccent
        case .snippets: return Theme.Colors.systemAccent
        case .quicklinks: return Theme.Colors.launcherAccent
        case .emoji: return Theme.Colors.emojiAccent
        case .calculator: return Theme.Colors.calculatorAccent
        case .windowManagement: return Theme.Colors.launcherAccent
        case .about: return Theme.Colors.brand
        }
    }
}

enum SettingsGroup: String, CaseIterable, Identifiable, Sendable {
    case preferences, features, about

    var id: String { rawValue }

    var title: String {
        switch self {
        case .preferences: return "Preferences"
        case .features: return "Features"
        case .about: return ""
        }
    }

    var tabs: [SettingsTab] {
        SettingsTab.allCases.filter { $0.group == self }
    }
}

@MainActor
private final class SettingsNavigationModel: ObservableObject {
    @Published var route: SettingsRoute

    init(route: SettingsRoute) {
        self.route = route
    }

    func navigate(to route: SettingsRoute) {
        self.route = route
    }

    func select(_ tab: SettingsTab) {
        navigate(to: SettingsRoute(tab: tab))
    }
}

struct SettingsRootView: View {
    @StateObject private var navigation: SettingsNavigationModel

    private struct SidebarGroup: Identifiable {
        let group: SettingsGroup
        let tabs: [SettingsTab]
        var id: String { group.id }
    }

    init(initialRoute: SettingsRoute = .general) {
        _navigation = StateObject(wrappedValue: SettingsNavigationModel(route: initialRoute))
    }

    private var sidebarGroups: [SidebarGroup] {
        SettingsGroup.allCases.map { SidebarGroup(group: $0, tabs: $0.tabs) }
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Theme.Colors.panelSurface.ignoresSafeArea())
        .background(VisualEffectView().ignoresSafeArea())
        .tint(Theme.Colors.textSecondary)
        .onReceive(NotificationCenter.default.publisher(for: .opencastSelectSettingsRoute)) {
            note in
            guard let route = note.object as? SettingsRoute else { return }
            navigation.navigate(to: route)
        }
    }

    private var content: some View {
        pane(for: navigation.route.tab)
            .environment(\.settingsDestination, navigation.route.destination)
            .id(navigation.route.tab)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    @ViewBuilder
    private func pane(for tab: SettingsTab) -> some View {
        switch tab {
        case .general: GeneralSettingsView()
        case .hyperKey: HyperKeySettingsView()
        case .launcher: LauncherSettingsView()
        case .commands: CommandsSettingsView()
        case .clipboard: ClipboardSettingsView()
        case .snippets: SnippetSettingsView()
        case .quicklinks: QuicklinkSettingsView()
        case .emoji: EmojiSettingsView()
        case .calculator: CalculatorSettingsView()
        case .windowManagement: WindowManagementSettingsView()
        case .about: AboutView()
        }
    }

    private var sidebar: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: Theme.Settings.Layout.groupSpacing) {
                ForEach(sidebarGroups) { section in
                    VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                        if !section.group.title.isEmpty {
                            Text(section.group.title.uppercased())
                                .font(Theme.Typography.caption2Semibold)
                                .foregroundStyle(Theme.Colors.textTertiary)
                                .tracking(0.6)
                                .padding(.horizontal, Theme.Spacing.lg)
                        }

                        ForEach(section.tabs) { item in
                            sidebarRow(item)
                                .padding(.horizontal, Theme.Settings.Layout.sidebarInset)
                        }
                    }
                }
            }
            .padding(.top, Theme.Settings.Layout.sidebarTopInset)
            .padding(.bottom, Theme.Spacing.xxl)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlayScroller(disablesElasticity: true)
        .frame(width: Theme.Settings.Size.sidebarWidth)
        .frame(maxHeight: .infinity)
        .background(
            ZStack(alignment: .trailing) {
                Theme.Settings.Colors.sidebarDimming
                Rectangle()
                    .fill(Theme.Settings.Colors.sidebarSeparator)
                    .frame(width: 1)
            }
            .ignoresSafeArea()
        )
    }

    private func sidebarRow(_ item: SettingsTab) -> some View {
        SidebarRow(
            title: item.title,
            systemImage: item.systemImage,
            tint: item.tint,
            isSelected: navigation.route.tab == item
        ) {
            navigation.select(item)
        }
    }
}

private struct SidebarRow: View {
    let title: String
    let systemImage: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void

    @State private var hovering = false
    @FocusState private var focused: Bool

    var body: some View {
        Button(action: action) {
            HStack(spacing: Theme.Spacing.lg) {
                Image(systemName: systemImage)
                    .font(Theme.Typography.iconMediumSmall)
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isSelected ? tint : Theme.Colors.textSecondary)
                    .frame(width: Theme.Settings.Size.sidebarIcon)

                Text(title)
                    .font(Theme.Typography.callout.weight(isSelected ? .medium : .regular))
                    .lineLimit(1)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, Theme.Spacing.lg)
            .frame(height: Theme.Settings.Size.sidebarRowHeight)
            .background(
                RoundedRectangle(
                    cornerRadius: Theme.Settings.Radius.navigation,
                    style: .continuous
                )
                .fill(rowFill)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(tint)
                        .frame(
                            width: Theme.Spacing.xxs,
                            height: Theme.Settings.Size.sidebarSelectionHeight
                        )
                        .padding(.leading, Theme.Spacing.xs)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .opacity(focused ? 1 : 0.96)
        .onHover { hovering = $0 }
    }

    private var rowFill: Color {
        if isSelected { return Theme.Settings.Colors.navigationSelection }
        if hovering || focused { return Theme.Settings.Colors.navigationHover }
        return .clear
    }
}
