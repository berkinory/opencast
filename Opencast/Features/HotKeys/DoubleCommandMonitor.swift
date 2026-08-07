import AppKit

extension DoubleModifier {
    var eventFlag: NSEvent.ModifierFlags {
        switch self {
        case .command: return .command
        case .option: return .option
        case .control: return .control
        }
    }
}

@MainActor
final class DoubleModifierMonitor: HealthCheckable {
    var onDoubleModifier: ((DoubleModifier) -> Void)?
    weak var healthTicker: HealthTicker?
    var isPaused = false {
        didSet {
            if isPaused { resetDetectors() }
        }
    }

    private var detectors = Dictionary(
        uniqueKeysWithValues: DoubleModifier.allCases.map { ($0, DoubleModifierDetector()) })
    private var monitors: [Any] = []

    func start() {
        stop()
        let eventMask: NSEvent.EventTypeMask = [.flagsChanged, .keyDown]

        if let monitor = NSEvent.addGlobalMonitorForEvents(
            matching: eventMask,
            handler: { [weak self] event in self?.handle(event) }
        ) {
            monitors.append(monitor)
        }
        if let monitor = NSEvent.addLocalMonitorForEvents(
            matching: eventMask,
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
        resetDetectors()
        healthTicker?.unsubscribe(self)
    }

    func healthCheck() {
        guard !isPaused, monitors.isEmpty else { return }
        start()
    }

    private func handle(_ event: NSEvent) {
        guard !isPaused else { return }
        let time = ProcessInfo.processInfo.systemUptime
        switch event.type {
        case .keyDown:
            for modifier in DoubleModifier.allCases {
                detectors[modifier]?.keyDown()
            }
        case .flagsChanged:
            let flags = event.modifierFlags.intersection(Self.trackedModifierFlags)
            for modifier in DoubleModifier.allCases {
                guard var detector = detectors[modifier] else { continue }
                let otherFlags = Self.trackedModifierFlags.subtracting(modifier.eventFlag)
                let recognized = detector.flagsChanged(
                    modifierIsDown: flags.contains(modifier.eventFlag),
                    otherModifierIsDown: !flags.intersection(otherFlags).isEmpty,
                    at: time
                )
                detectors[modifier] = detector
                if recognized {
                    onDoubleModifier?(modifier)
                    break
                }
            }
        default:
            break
        }
    }

    private func resetDetectors() {
        for modifier in DoubleModifier.allCases {
            detectors[modifier]?.reset()
        }
    }

    private static let trackedModifierFlags: NSEvent.ModifierFlags = [
        .command, .option, .control, .shift,
    ]
}
