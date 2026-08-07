import Foundation
import Combine

@MainActor
final class ExtensionScheduler: ObservableObject {
    private static let maxMenuBarSnapshots = 32
    @Published var backgroundEnabled: Bool {
        didSet {
            defaults.set(backgroundEnabled, forKey: enabledKey)
            if backgroundEnabled { tick(force: true) } else { cancelRunners() }
        }
    }
    @Published private(set) var menuBarSnapshots: [ExtensionMenuBarSnapshot] = []
    @Published private(set) var lastMetrics: ExtensionRuntimeMetrics?

    private let capabilityBroker: ExtensionCapabilityBroker
    private let snapshotStore: ExtensionSnapshotStore
    private let defaults = UserDefaults.standard
    private let enabledKey: String
    private var commands: [ExtensionCommand] = []
    private var runners: [String: ExtensionInvocationRunner] = [:]
    private var timer: Timer?
    private var lastRuns: [String: Date] = [:]

    init(capabilityBroker: ExtensionCapabilityBroker, snapshotStore: ExtensionSnapshotStore = ExtensionSnapshotStore())
    {
        self.capabilityBroker = capabilityBroker
        self.snapshotStore = snapshotStore
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        enabledKey = "extensionBackgroundEnabled.\(bundleID)"
        backgroundEnabled = true
        defaults.set(true, forKey: enabledKey)
    }

    func start(commands: [ExtensionCommand]) {
        self.commands = commands
        lastRuns = Dictionary(
            uniqueKeysWithValues: commands.compactMap { command in
                guard let date = defaults.object(forKey: lastRunKey(command.id)) as? Date else { return nil }
                return (command.id, date)
            })
        loadSnapshots()
        timer?.invalidate()
        guard backgroundEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(force: false) }
        }
    }

    func reload(commands: [ExtensionCommand]) {
        self.commands = commands
        loadSnapshots()
        timer?.invalidate()
        guard backgroundEnabled else { return }
        timer = Timer.scheduledTimer(withTimeInterval: 5, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick(force: false) }
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        cancelRunners()
    }

    func command(for snapshot: ExtensionMenuBarSnapshot) -> ExtensionCommand? {
        commands.first { $0.id == snapshot.commandID }
    }

    private func loadSnapshots() {
        menuBarSnapshots = Array(
            commands.filter(\.menuBar).compactMap { snapshotStore.load(commandID: $0.id) }
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
                .prefix(Self.maxMenuBarSnapshots)
        )
        lastMetrics =
            commands.compactMap { snapshotStore.loadMetrics(commandID: $0.id) }
            .sorted { $0.timestamp > $1.timestamp }.first
    }

    private func tick(force: Bool) {
        guard backgroundEnabled else { return }
        let now = Date()
        for command in commands {
            guard let interval = interval(for: command.interval),
                runners[command.id] == nil,
                force || lastRuns[command.id].map({ now.timeIntervalSince($0) >= interval }) ?? true
            else { continue }
            lastRuns[command.id] = now
            defaults.set(now, forKey: lastRunKey(command.id))
            begin(command)
        }
        if !menuBarSnapshots.isEmpty {
            menuBarSnapshots = menuBarSnapshots
        }
    }

    private func begin(_ command: ExtensionCommand) {
        let runner = ExtensionInvocationRunner(
            command: command,
            capabilityBroker: capabilityBroker,
            onRender: { [weak self] snapshot in
                guard command.menuBar, snapshot.root == "menuBarSnapshot" else { return }
                let stored = ExtensionMenuBarSnapshot(
                    commandID: command.id,
                    title: command.title,
                    subtitle: command.subtitle,
                    snapshot: snapshot,
                    updatedAt: Date(),
                    staleAfterSeconds: self?.interval(for: command.interval).map { $0 * 3 }
                )
                self?.snapshotStore.save(stored)
                let current = self?.menuBarSnapshots.filter { $0.commandID != command.id } ?? []
                self?.menuBarSnapshots = Array((current + [stored]).prefix(Self.maxMenuBarSnapshots))
            },
            onFinish: { [weak self] metrics, _ in
                guard let self else { return }
                self.runners[command.id] = nil
                if let metrics {
                    self.lastMetrics = metrics
                    self.snapshotStore.saveMetrics(metrics)
                }
            }
        )
        runners[command.id] = runner
        runner.start()
    }

    private func cancelRunners() {
        Array(runners.values).forEach { $0.cancel() }
        runners.removeAll()
    }

    private func interval(for value: String?) -> TimeInterval? {
        guard let value else { return nil }
        let parts = value.split(separator: " ")
        guard parts.count == 2, let count = Double(parts[0]), count > 0 else { return nil }
        let seconds: Double
        switch parts[1] {
        case "second", "seconds": seconds = count
        case "minute", "minutes": seconds = count * 60
        case "hour", "hours": seconds = count * 3_600
        case "day", "days": seconds = count * 86_400
        default: return nil
        }
        return seconds >= 5 ? seconds : nil
    }

    private func lastRunKey(_ commandID: String) -> String {
        "extensionLastRun.\(enabledKey).\(commandID)"
    }
}
