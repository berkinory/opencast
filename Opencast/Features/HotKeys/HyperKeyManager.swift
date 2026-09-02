@preconcurrency import ApplicationServices
import AppKit
import Carbon.HIToolbox

enum HyperKey: String, CaseIterable, Identifiable, Sendable {
    case capsLock
    case rightCommand
    case rightOption
    case rightControl

    var id: String { rawValue }

    var title: String {
        switch self {
        case .capsLock: return "Caps Lock"
        case .rightCommand: return "Right Command"
        case .rightOption: return "Right Option"
        case .rightControl: return "Right Control"
        }
    }

    var keyCode: CGKeyCode {
        switch self {
        case .capsLock: return CGKeyCode(kVK_CapsLock)
        case .rightCommand: return CGKeyCode(kVK_RightCommand)
        case .rightOption: return CGKeyCode(kVK_RightOption)
        case .rightControl: return CGKeyCode(kVK_RightControl)
        }
    }

    var symbol: String {
        switch self {
        case .capsLock: return "⇪"
        case .rightCommand: return "⌘"
        case .rightOption: return "⌥"
        case .rightControl: return "⌃"
        }
    }
}

enum HyperTapBehavior: String, CaseIterable, Identifiable, Sendable {
    case original
    case nothing

    var id: String { rawValue }

    var title: String {
        switch self {
        case .original: return "Keep original key"
        case .nothing: return "Nothing"
        }
    }

    var subtitle: String {
        switch self {
        case .original: return "A quick tap behaves like the selected key."
        case .nothing: return "A quick tap does nothing."
        }
    }
}

@MainActor
final class HyperKeyManager: ObservableObject, HealthCheckable {
    @Published private(set) var isActive = false
    @Published private(set) var needsAccessibility = false

    private let settings: AppSettings
    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var isHeld = false
    private var usedAsModifier = false
    private static let replayMarker: Int64 = 0x4F50454E43415354

    init(settings: AppSettings) {
        self.settings = settings
    }

    func start() {
        stop()
        guard settings.hyperKeyEnabled else {
            needsAccessibility = false
            return
        }
        guard Permissions.isAccessibilityTrusted() else {
            needsAccessibility = true
            return
        }

        let eventMask =
            (CGEventMask(1) << CGEventType.flagsChanged.rawValue)
            | (CGEventMask(1) << CGEventType.keyDown.rawValue)
            | (CGEventMask(1) << CGEventType.keyUp.rawValue)
            | (CGEventMask(1) << CGEventType.leftMouseDown.rawValue)
            | (CGEventMask(1) << CGEventType.rightMouseDown.rawValue)
        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .defaultTap,
                eventsOfInterest: eventMask,
                callback: { proxy, type, event, userInfo in
                    guard let userInfo else { return Unmanaged.passUnretained(event) }
                    let manager = Unmanaged<HyperKeyManager>.fromOpaque(userInfo).takeUnretainedValue()
                    return MainActor.assumeIsolated {
                        manager.handle(proxy: proxy, type: type, event: event)
                    }
                },
                userInfo: userInfo
            )
        else {
            needsAccessibility = true
            return
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource {
            CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        CGEvent.tapEnable(tap: tap, enable: true)
        needsAccessibility = false
        isActive = true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        isHeld = false
        usedAsModifier = false
        isActive = false
    }

    func restart() {
        start()
    }

    func healthCheck() {
        guard settings.hyperKeyEnabled, !isActive else { return }
        start()
    }

    private func handle(
        proxy: CGEventTapProxy,
        type: CGEventType,
        event: CGEvent
    ) -> Unmanaged<CGEvent>? {
        if event.getIntegerValueField(.eventSourceUserData) == Self.replayMarker {
            return Unmanaged.passUnretained(event)
        }
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap { CGEvent.tapEnable(tap: eventTap, enable: true) }
            return Unmanaged.passUnretained(event)
        }

        let keyCode = CGKeyCode(event.getIntegerValueField(.keyboardEventKeycode))
        if type == .flagsChanged, keyCode == settings.hyperKey.keyCode {
            if isHeld {
                isHeld = false
                let shouldReplay = !usedAsModifier
                usedAsModifier = false
                if shouldReplay { replayTap() }
            } else {
                isHeld = true
                usedAsModifier = false
            }
            return nil
        }

        guard isHeld else { return Unmanaged.passUnretained(event) }
        switch type {
        case .keyDown, .flagsChanged:
            if keyCode != settings.hyperKey.keyCode { usedAsModifier = true }
            event.flags.formUnion([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        case .keyUp:
            event.flags.formUnion([.maskCommand, .maskAlternate, .maskControl, .maskShift])
        case .leftMouseDown, .rightMouseDown:
            usedAsModifier = true
        default:
            break
        }
        return Unmanaged.passUnretained(event)
    }

    private func replayTap() {
        switch settings.hyperTapBehavior {
        case .nothing: return
        case .original: postKey(settings.hyperKey.keyCode)
        }
    }

    private func postKey(_ keyCode: CGKeyCode) {
        let source = CGEventSource(stateID: .combinedSessionState)
        let down = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: true)
        let up = CGEvent(keyboardEventSource: source, virtualKey: keyCode, keyDown: false)
        down?.flags = []
        up?.flags = []
        down?.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        up?.setIntegerValueField(.eventSourceUserData, value: Self.replayMarker)
        down?.post(tap: .cghidEventTap)
        up?.post(tap: .cghidEventTap)
    }
}
