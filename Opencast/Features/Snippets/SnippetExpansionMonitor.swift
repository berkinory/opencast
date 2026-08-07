import AppKit
import Carbon.HIToolbox

@MainActor
final class SnippetExpansionMonitor: HealthCheckable {
    private let store: SnippetStore
    private let settings: AppSettings
    private var monitors: [Any] = []
    private var typedBuffer = ""
    weak var healthTicker: HealthTicker?

    init(store: SnippetStore, settings: AppSettings) {
        self.store = store
        self.settings = settings
    }

    func start() {
        stop()
        let mask: NSEvent.EventTypeMask = [.keyDown, .flagsChanged, .leftMouseDown, .rightMouseDown]
        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: mask, handler: { [weak self] event in self?.handle(event) }
        ) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: mask,
            handler: { [weak self] event in
                self?.handle(event)
                return event
            }
        ) {
            monitors.append(monitor)
        }
        healthTicker?.subscribe(self)
    }

    func stop() {
        for monitor in monitors { NSEvent.removeMonitor(monitor) }
        monitors = []
        typedBuffer = ""
        healthTicker?.unsubscribe(self)
    }

    func healthCheck() {
        guard monitors.isEmpty else { return }
        start()
    }

    private func handle(_ event: NSEvent) {
        guard settings.snippetsEnabled else {
            typedBuffer = ""
            return
        }
        guard isEligibleTarget else {
            typedBuffer = ""
            return
        }

        switch event.type {
        case .keyDown:
            guard event.modifierFlags.intersection([.command, .control, .option]).isEmpty else {
                typedBuffer = ""
                return
            }
            if event.keyCode == CGKeyCode(kVK_Delete) {
                if !typedBuffer.isEmpty { typedBuffer.removeLast() }
                return
            }
            guard let characters = event.characters, !characters.isEmpty else {
                typedBuffer = ""
                return
            }
            typedBuffer.append(characters)
            typedBuffer = String(typedBuffer.suffix(128))
            expandMatchingSnippet()
        case .flagsChanged, .leftMouseDown, .rightMouseDown:
            typedBuffer = ""
        default:
            break
        }
    }

    private var isEligibleTarget: Bool {
        guard let bundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier else { return false }
        guard bundleID != Bundle.main.bundleIdentifier else { return false }
        return !settings.snippetDisabledApps.contains(bundleID)
    }

    private func expandMatchingSnippet() {
        guard
            let snippet = store.snippets
                .filter({ !$0.keyword.isEmpty && typedBuffer.hasSuffix($0.keyword) })
                .filter(isWordBoundaryMatch)
                .max(by: { $0.keyword.count < $1.keyword.count })
        else { return }
        guard Permissions.ensureAccessibility() else {
            typedBuffer = ""
            return
        }
        postBackspaces(snippet.keyword.count)
        typedBuffer = ""
        Paster.pasteString(snippet.content, previousApp: nil)
    }

    private func isWordBoundaryMatch(_ snippet: Snippet) -> Bool {
        let prefixCount = typedBuffer.count - snippet.keyword.count
        guard prefixCount > 0 else { return true }
        let prefix = typedBuffer.dropLast(snippet.keyword.count)
        guard let last = prefix.last else { return true }
        return !last.isLetter && !last.isNumber
    }

    private func postBackspaces(_ count: Int) {
        guard count > 0 else { return }
        let source = CGEventSource(stateID: .combinedSessionState)
        for _ in 0..<count {
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: true)
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_Delete), keyDown: false)
            down?.post(tap: .cghidEventTap)
            up?.post(tap: .cghidEventTap)
        }
    }
}
