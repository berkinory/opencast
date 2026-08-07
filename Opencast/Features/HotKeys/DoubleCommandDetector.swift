import Foundation

enum DoubleModifier: String, CaseIterable, Hashable, Sendable {
    case command
    case option
    case control

    var symbol: String {
        switch self {
        case .command: return "⌘"
        case .option: return "⌥"
        case .control: return "⌃"
        }
    }
}

struct DoubleModifierDetector: Sendable {
    let maximumInterval: TimeInterval

    private(set) var modifierDown = false
    private var cycleValid = true
    private var previousRelease: TimeInterval?

    init(maximumInterval: TimeInterval = 0.35) {
        self.maximumInterval = maximumInterval
    }

    @discardableResult
    mutating func flagsChanged(
        modifierIsDown: Bool,
        otherModifierIsDown: Bool,
        at time: TimeInterval
    ) -> Bool {
        if modifierIsDown == modifierDown {
            if modifierDown, otherModifierIsDown { cycleValid = false }
            return false
        }

        if modifierIsDown {
            modifierDown = true
            cycleValid = !otherModifierIsDown
            if let previousRelease, time - previousRelease > maximumInterval {
                self.previousRelease = nil
            }
            return false
        }

        let recognized =
            modifierDown
            && cycleValid
            && !otherModifierIsDown
            && previousRelease.map { time - $0 <= maximumInterval } == true

        if modifierDown, cycleValid, !otherModifierIsDown {
            previousRelease = recognized ? nil : time
        } else {
            previousRelease = nil
        }
        modifierDown = false
        cycleValid = true
        return recognized
    }

    mutating func keyDown() {
        if modifierDown { cycleValid = false }
    }

    mutating func reset() {
        modifierDown = false
        cycleValid = true
        previousRelease = nil
    }
}
