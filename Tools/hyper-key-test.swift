import AppKit
import Carbon.HIToolbox

@MainActor
final class AppSettings {
    var hyperKeyEnabled = true
    var hyperKey: HyperKey = .rightCommand
    var hyperTapBehavior: HyperTapBehavior = .nothing
}

enum Permissions {
    static func isAccessibilityTrusted() -> Bool { false }
}

@main
@MainActor
struct HyperKeyTests {
    static func main() {
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            if !condition {
                failures += 1
                print("FAIL: \(label)")
            }
        }
        let hyper: CGEventFlags = [.maskCommand, .maskAlternate, .maskControl, .maskShift]
        let triggers: [(HyperKey, CGEventFlags)] = [
            (.capsLock, .maskAlphaShift),
            (.rightCommand, CGEventFlags(rawValue: 0x10).union(.maskCommand)),
            (.rightOption, CGEventFlags(rawValue: 0x40).union(.maskAlternate)),
            (.rightControl, CGEventFlags(rawValue: 0x2000).union(.maskControl)),
        ]
        for (trigger, pressedFlags) in triggers {
            for interruption in [CGEventType.tapDisabledByTimeout, .tapDisabledByUserInput] {
                let settings = AppSettings()
                settings.hyperKey = trigger
                let manager = HyperKeyManager(settings: settings)
                func send(_ type: CGEventType, key: CGKeyCode = 0, flags: CGEventFlags = []) -> CGEvent {
                    let event = CGEvent(keyboardEventSource: nil, virtualKey: key, keyDown: type != .keyUp)!
                    event.flags = flags
                    _ = manager.handle(type: type, event: event)
                    return event
                }
                _ = send(.flagsChanged, key: settings.hyperKey.keyCode, flags: pressedFlags)
                expect(send(.keyDown).flags.intersection(hyper) == hyper, "held trigger applies Hyper")
                _ = send(interruption)
                expect(send(.keyDown).flags.intersection(hyper).isEmpty, "interruption clears held modifiers")
                _ = send(.flagsChanged, key: settings.hyperKey.keyCode)
                expect(send(.keyDown).flags.intersection(hyper).isEmpty, "release after interruption stays released")
                _ = send(.flagsChanged, key: settings.hyperKey.keyCode, flags: pressedFlags)
                _ = send(.flagsChanged, key: settings.hyperKey.keyCode, flags: pressedFlags)
                expect(send(.keyDown).flags.intersection(hyper) == hyper, "duplicate press does not release Hyper")
                _ = send(.flagsChanged, key: settings.hyperKey.keyCode)
                expect(send(.keyDown).flags.intersection(hyper).isEmpty, "normal release clears Hyper")
                _ = send(.flagsChanged, key: settings.hyperKey.keyCode, flags: pressedFlags)
                manager.stop()
                expect(send(.keyDown).flags.intersection(hyper).isEmpty, "stop clears held Hyper")
            }
        }
        guard failures == 0 else { exit(1) }
        print("Hyper event recovery tests passed")
    }
}
