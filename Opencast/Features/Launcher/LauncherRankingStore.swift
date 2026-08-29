import Foundation

/// One learned launcher choice for a normalized query prefix. An empty query is the item's global usage record.
struct LauncherRankingRecord: Codable, Hashable, Sendable {
    let itemKey: String
    let query: String
    var count: Double
    var lastUsed: Date
}

/// Learns launcher choices and persists bounded, on-device-only adaptive history under `~/Library/Application Support/<bundle-id>/`.
@MainActor
final class LauncherRankingStore: ObservableObject {
    private static let cap = 1_000
    private static let maximumAffinity = 10_000
    private static let queryHalfLifeDays = 30.0
    private static let globalHalfLifeDays = 60.0

    private let fileURL: URL
    private let now: () -> Date

    @Published private(set) var records: [LauncherRankingRecord]
    /// AppIndex includes this in its one-entry cache key, invalidating a result after a visit/reset.
    private(set) var revision = 0

    private var lookup: [String: [String: LauncherRankingRecord]]?
    private var writeTask: Task<Void, Never>?

    init(fileURL: URL? = nil, now: @escaping () -> Date = Date.init) {
        self.fileURL = fileURL ?? Self.defaultFileURL()
        self.now = now

        if let data = try? Data(contentsOf: self.fileURL),
            let decoded = try? JSONDecoder().decode([LauncherRankingRecord].self, from: data)
        {
            records = decoded.filter { !$0.itemKey.isEmpty && $0.count > 0 }
        } else {
            records = []
        }
    }

    var isEmpty: Bool { records.isEmpty }

    func flush() async {
        await writeTask?.value
    }

    /// Records global usage plus every prefix of a submitted query. An empty query records global usage only.
    func record(itemKey: String, query: String) {
        guard !itemKey.isEmpty else { return }
        let query = Self.normalize(query)
        let timestamp = now()

        visit(itemKey: itemKey, query: "", at: timestamp)
        for prefix in Self.prefixes(of: query) {
            visit(itemKey: itemKey, query: prefix, at: timestamp)
        }

        if records.count > Self.cap {
            records =
                records
                .map { (record: $0, affinity: retentionAffinity($0, at: timestamp)) }
                .sorted {
                    $0.affinity != $1.affinity
                        ? $0.affinity > $1.affinity : $0.record.lastUsed > $1.record.lastUsed
                }
                .prefix(Self.cap)
                .map(\.record)
        }
        didMutate()
    }

    /// Query-specific confidence on a 0...10,000 scale. Three recent selections are enough for a controlled one-tier promotion; stale history decays below that threshold.
    func affinities(query: String) -> [String: Int] {
        let query = Self.normalize(query)
        guard !query.isEmpty, let learned = rankingLookup()[query] else { return [:] }
        let timestamp = now()
        return learned.mapValues {
            affinity($0, at: timestamp, halfLifeDays: Self.queryHalfLifeDays)
        }
    }

    /// Weak item-wide usage signal, used only as a final tie-break after fuzzy quality and query learning.
    func globalAffinities() -> [String: Int] {
        guard let learned = rankingLookup()[""] else { return [:] }
        let timestamp = now()
        return learned.mapValues {
            affinity($0, at: timestamp, halfLifeDays: Self.globalHalfLifeDays)
        }
    }

    func hasRanking(for itemKey: String) -> Bool {
        records.contains { $0.itemKey == itemKey }
    }

    func reset(itemKey: String) {
        let oldCount = records.count
        records.removeAll { $0.itemKey == itemKey }
        guard records.count != oldCount else { return }
        didMutate()
    }

    func resetAll() {
        guard !records.isEmpty else { return }
        records = []
        didMutate()
    }

    /// `locale: nil` is the locale-independent canonical form: these are persisted lookup keys, and a locale-sensitive fold maps "I" to "ı" under Turkish, orphaning every record keyed on the dotted form.
    static func normalize(_ query: String) -> String {
        query
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
    }

    private func visit(itemKey: String, query: String, at timestamp: Date) {
        if let index = records.firstIndex(where: {
            $0.itemKey == itemKey && $0.query == query
        }) {
            let halfLife = query.isEmpty ? Self.globalHalfLifeDays : Self.queryHalfLifeDays
            let decayed = effectiveCount(records[index], at: timestamp, halfLifeDays: halfLife)
            // Adaptive input history approaches 10 without reaching an irreversible count; a fresh choice always matters while old evidence has already decayed.
            records[index].count = min(10, decayed * 0.9 + 1)
            records[index].lastUsed = timestamp
        } else {
            records.append(
                LauncherRankingRecord(
                    itemKey: itemKey, query: query, count: 1, lastUsed: timestamp))
        }
    }

    private func affinity(
        _ record: LauncherRankingRecord, at timestamp: Date, halfLifeDays: Double
    ) -> Int {
        let count = min(10, effectiveCount(record, at: timestamp, halfLifeDays: halfLifeDays))
        return min(Self.maximumAffinity, Int((count * 1_000).rounded()))
    }

    private func effectiveCount(
        _ record: LauncherRankingRecord, at timestamp: Date, halfLifeDays: Double
    ) -> Double {
        let ageInDays = max(0, timestamp.timeIntervalSince(record.lastUsed)) / 86_400
        return record.count * exp(-log(2) * ageInDays / halfLifeDays)
    }

    private func retentionAffinity(_ record: LauncherRankingRecord, at timestamp: Date) -> Int {
        affinity(
            record, at: timestamp,
            halfLifeDays: record.query.isEmpty
                ? Self.globalHalfLifeDays : Self.queryHalfLifeDays)
    }

    private static func prefixes(of query: String) -> [String] {
        guard !query.isEmpty else { return [] }
        let limit = min(query.count, 64)
        var result: [String] = []
        result.reserveCapacity(limit)
        var end = query.startIndex
        for _ in 0..<limit {
            end = query.index(after: end)
            result.append(String(query[..<end]))
        }
        return result
    }

    private func rankingLookup() -> [String: [String: LauncherRankingRecord]] {
        if let lookup { return lookup }
        var built: [String: [String: LauncherRankingRecord]] = [:]
        for record in records {
            built[record.query, default: [:]][record.itemKey] = record
        }
        lookup = built
        return built
    }

    private func didMutate() {
        lookup = nil
        revision &+= 1
        let snapshot = records
        let fileURL = fileURL
        let previous = writeTask
        writeTask = Task.detached(priority: .utility) {
            await previous?.value
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static func defaultFileURL() -> URL {
        AppPaths.applicationSupport().appendingPathComponent("launcher-ranking.json")
    }
}
