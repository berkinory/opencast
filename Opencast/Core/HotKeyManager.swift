import Foundation

/// Owns all global shortcut bindings: persistence, Carbon registration (via `HotKeyCenter`), conflict lookup, and dispatch.
@MainActor
final class HotKeyManager: ObservableObject, HealthCheckable {
    var onTogglePalette: (() -> Void)?
    var onToggleClipboard: (() -> Void)?
    var onToggleEmoji: (() -> Void)?
    var onRunCommand: ((String) -> Void)?
    var onRunWindowCommand: ((WindowCommand.ID) -> Void)?

    /// The recorder currently capturing keystrokes, or `nil`; keeping this as plain app state makes recorders glitch-free, and any active recorder pauses Carbon so the typed combo can't fire a hotkey.
    @Published var recordingAction: HotKeyAction? {
        didSet {
            let paused = recordingAction != nil
            center.isPaused = paused
            doubleModifierMonitor.isPaused = paused
        }
    }

    private let center = HotKeyCenter()
    private let doubleModifierMonitor = DoubleModifierMonitor()
    private let boundKey = "boundAppBundleIDs"
    private let boundPaneKey = "boundPaneBundleIDs"
    private let boundCommandKey = "boundCommandIDs"
    private let decoder = JSONDecoder()
    private let encoder = JSONEncoder()
    private let entries: () -> [AppEntry]
    private var bindings: [HotKeyAction: HotKeyBinding] = [:]
    private var candidateActionsCache: [HotKeyAction]?
    @Published private(set) var unavailableActions: Set<HotKeyAction> = []
    weak var healthTicker: HealthTicker? {
        didSet {
            oldValue?.unsubscribe(self)
            healthTicker?.subscribe(self)
            doubleModifierMonitor.healthTicker = healthTicker
        }
    }

    init(entries: @escaping () -> [AppEntry]) {
        self.entries = entries
    }

    func start() {
        bindings.removeAll(keepingCapacity: true)
        candidateActionsCache = nil
        unavailableActions.removeAll(keepingCapacity: true)
        for action in candidateActions { bindings[action] = storedBinding(for: action) }
        register(.togglePalette)
        register(.toggleClipboard)
        register(.toggleEmoji)
        for bundleID in boundBundleIDs { register(.app(bundleID: bundleID)) }
        for bundleID in boundPaneBundleIDs { register(.settingsPane(bundleID: bundleID)) }
        for id in boundCommandIDs { register(.command(id: id)) }
        for command in WindowCommandCatalog.all {
            register(.windowCommand(id: command.id))
        }
        doubleModifierMonitor.onDoubleModifier = { [weak self] modifier in
            self?.performDoubleModifier(modifier)
        }
        doubleModifierMonitor.start()
    }

    /// Bundle IDs that currently have a per-app hotkey — lets `start()` know which records to load and lets launcher rows show keycaps.
    var boundBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundKey) ?? []
    }

    /// Settings-pane bundle IDs with a hotkey — same role as `boundBundleIDs`, own namespace.
    var boundPaneBundleIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundPaneKey) ?? []
    }

    var boundCommandIDs: [String] {
        UserDefaults.standard.stringArray(forKey: boundCommandKey) ?? []
    }

    func binding(for action: HotKeyAction) -> HotKeyBinding? {
        bindings[action]
    }

    func isRegistrationUnavailable(for action: HotKeyAction) -> Bool {
        unavailableActions.contains(action)
    }

    func healthCheck() {
        center.retryUnregistered()
        for action in candidateActions {
            guard case .key = binding(for: action) else { continue }
            setRegistrationState(for: action)
        }
    }

    private func storedBinding(for action: HotKeyAction) -> HotKeyBinding? {
        guard let json = UserDefaults.standard.string(forKey: action.defaultsKey) else { return nil }
        switch json {
        case "doubleCommand": return .doubleModifier(.command)
        case "doubleOption": return .doubleModifier(.option)
        case "doubleControl": return .doubleModifier(.control)
        default: break
        }
        guard let data = json.data(using: .utf8),
            let shortcut = try? decoder.decode(KeyShortcut.self, from: data)
        else { return nil }
        return .key(shortcut)
    }

    func shortcut(for action: HotKeyAction) -> KeyShortcut? {
        guard case .key(let shortcut) = binding(for: action) else { return nil }
        return shortcut
    }

    /// Persists (or clears, when `nil`) the binding, swaps the live registration, and publishes so the launcher and recorders re-render.
    func setBinding(_ binding: HotKeyBinding?, for action: HotKeyAction) {
        switch binding {
        case .key(let shortcut):
            guard
                let data = try? encoder.encode(shortcut),
                let json = String(data: data, encoding: .utf8)
            else { return }
            bindings[action] = binding
            unavailableActions.remove(action)
            UserDefaults.standard.set(json, forKey: action.defaultsKey)
            register(action)
        case .doubleModifier(let modifier):
            let value: String
            switch modifier {
            case .command: value = "doubleCommand"
            case .option: value = "doubleOption"
            case .control: value = "doubleControl"
            }
            bindings[action] = binding
            unavailableActions.remove(action)
            UserDefaults.standard.set(value, forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        case nil:
            bindings[action] = nil
            unavailableActions.remove(action)
            UserDefaults.standard.removeObject(forKey: action.defaultsKey)
            center.unregister(id: action.defaultsKey)
        }
        switch action {
        case .app(let bundleID):
            var set = Set(boundBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundKey)
        case .settingsPane(let bundleID):
            var set = Set(boundPaneBundleIDs)
            if binding == nil { set.remove(bundleID) } else { set.insert(bundleID) }
            UserDefaults.standard.set(Array(set), forKey: boundPaneKey)
        case .command(let id):
            var set = Set(boundCommandIDs)
            if binding == nil { set.remove(id) } else { set.insert(id) }
            UserDefaults.standard.set(Array(set), forKey: boundCommandKey)
        case .windowCommand:
            break
        case .togglePalette, .toggleClipboard, .toggleEmoji:
            break
        }
        candidateActionsCache = nil
        objectWillChange.send()
    }

    func setShortcut(_ shortcut: KeyShortcut?, for action: HotKeyAction) {
        setBinding(shortcut.map(HotKeyBinding.key), for: action)
    }

    /// The display name of whatever else `binding` is bound to (or `nil` if free), driving the recorder's "Used by …" message.
    func conflictOwner(of binding: HotKeyBinding, excluding action: HotKeyAction) -> String? {
        for candidate in candidateActions
        where candidate != action && self.binding(for: candidate) == binding {
            return displayName(of: candidate)
        }
        return nil
    }

    func conflictOwner(of shortcut: KeyShortcut, excluding action: HotKeyAction) -> String? {
        conflictOwner(of: .key(shortcut), excluding: action)
    }

    func displayName(of action: HotKeyAction) -> String {
        switch action {
        case .togglePalette:
            return "App Launcher"
        case .toggleClipboard:
            return "Clipboard History"
        case .toggleEmoji:
            return "Emoji & Symbols"
        case .app(let bundleID):
            let apps = entries()
            return apps.first { $0.kind == .application && $0.bundleID == bundleID }?.name
                ?? bundleID
        case .settingsPane(let bundleID):
            let apps = entries()
            return apps.first { $0.kind == .systemSettings && $0.bundleID == bundleID }?.name
                ?? bundleID
        case .command(let id):
            return entries().first { $0.id == id }?.name
                ?? CommandRegistry.all.first { $0.id == id }?.name
                ?? id
        case .windowCommand(let id):
            return WindowCommandCatalog.command(id: id)?.name ?? id.rawValue
        }
    }

    private func register(_ action: HotKeyAction) {
        center.unregister(id: action.defaultsKey)
        guard case .key(let shortcut) = binding(for: action) else { return }
        center.register(id: action.defaultsKey, shortcut: shortcut) { [weak self] in
            self?.perform(action)
        }
        setRegistrationState(for: action)
    }

    private func setRegistrationState(for action: HotKeyAction) {
        let unavailable = !center.isRegistered(id: action.defaultsKey)
        guard unavailableActions.contains(action) != unavailable else { return }
        if unavailable {
            unavailableActions.insert(action)
        } else {
            unavailableActions.remove(action)
        }
    }

    private func performDoubleModifier(_ modifier: DoubleModifier) {
        guard
            let action = candidateActions.first(where: {
                binding(for: $0) == .doubleModifier(modifier)
            })
        else { return }
        perform(action)
    }

    private var candidateActions: [HotKeyAction] {
        if let candidateActionsCache { return candidateActionsCache }
        var actions: [HotKeyAction] = [.togglePalette, .toggleClipboard, .toggleEmoji]
        actions += boundBundleIDs.map { .app(bundleID: $0) }
        actions += boundPaneBundleIDs.map { .settingsPane(bundleID: $0) }
        actions += boundCommandIDs.map { .command(id: $0) }
        actions += WindowCommandCatalog.all.map { .windowCommand(id: $0.id) }
        candidateActionsCache = actions
        return actions
    }

    private func perform(_ action: HotKeyAction) {
        switch action {
        case .togglePalette: onTogglePalette?()
        case .toggleClipboard: onToggleClipboard?()
        case .toggleEmoji: onToggleEmoji?()
        case .app(let bundleID): AppLauncher.toggle(bundleID: bundleID)
        case .settingsPane(let bundleID): AppLauncher.openSettingsPane(bundleID: bundleID)
        case .command(let id): onRunCommand?(id)
        case .windowCommand(let id): onRunWindowCommand?(id)
        }
    }
}
