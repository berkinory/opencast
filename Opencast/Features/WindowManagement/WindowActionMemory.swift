import CoreGraphics
import Foundation

struct WindowActionMemory<Key: Hashable> {
    struct Record: Equatable, Sendable {
        var restoreFrame: CGRect
        var appliedFrame: CGRect
        var command: WindowCommand.ID
    }

    struct Decision: Equatable, Sendable {
        var restoreFrame: CGRect
        var canRestore: Bool
        var lastTileCommand: WindowCommand.ID?
    }

    static var tolerance: CGFloat { 2 }

    var capacity: Int
    private var records: [Key: Record] = [:]
    private var order: [Key] = []

    init(capacity: Int = 64) {
        self.capacity = capacity
    }

    var count: Int { records.count }

    func record(for key: Key) -> Record? { records[key] }

    func decide(key: Key, currentFrame: CGRect) -> Decision {
        guard let record = records[key] else {
            return Decision(
                restoreFrame: currentFrame, canRestore: false, lastTileCommand: nil)
        }

        guard approximatelyEqual(currentFrame, record.appliedFrame) else {
            return Decision(
                restoreFrame: currentFrame, canRestore: true, lastTileCommand: nil)
        }

        let lastTileCommand =
            WindowLayout.isTileCommand(record.command) ? record.command : nil
        return Decision(
            restoreFrame: record.restoreFrame,
            canRestore: true,
            lastTileCommand: lastTileCommand)
    }

    mutating func commit(
        key: Key, command: WindowCommand.ID, decision: Decision, appliedFrame: CGRect
    ) {
        records[key] = Record(
            restoreFrame: decision.restoreFrame,
            appliedFrame: appliedFrame,
            command: command)
        touch(key)
    }

    mutating func forget(where predicate: (Key) -> Bool) {
        let doomed = records.keys.filter(predicate)
        guard !doomed.isEmpty else { return }
        for key in doomed { records.removeValue(forKey: key) }
        order.removeAll { doomed.contains($0) }
    }

    mutating func forget(key: Key) {
        guard records.removeValue(forKey: key) != nil else { return }
        order.removeAll { $0 == key }
    }

    private mutating func touch(_ key: Key) {
        order.removeAll { $0 == key }
        order.append(key)
        while order.count > capacity, let oldest = order.first {
            order.removeFirst()
            records.removeValue(forKey: oldest)
        }
    }

    private func approximatelyEqual(_ a: CGRect, _ b: CGRect) -> Bool {
        let tolerance = Self.tolerance
        return abs(a.minX - b.minX) <= tolerance && abs(a.minY - b.minY) <= tolerance
            && abs(a.width - b.width) <= tolerance && abs(a.height - b.height) <= tolerance
    }
}
