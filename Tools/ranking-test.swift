import Foundation

@main
struct RankingTest {
    @MainActor
    static func main() async {
        let fileURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("opencast-ranking-\(UUID().uuidString).json")
        defer { try? FileManager.default.removeItem(at: fileURL) }

        var clock = Date(timeIntervalSince1970: 2_000_000_000)
        let store = LauncherRankingStore(fileURL: fileURL) { clock }
        var failures = 0

        func check(_ description: String, _ condition: @autoclosure () -> Bool) {
            if condition() {
                print("PASS  \(description)")
            } else {
                print("FAIL  \(description)")
                failures += 1
            }
        }

        func affinity(_ store: LauncherRankingStore, _ itemKey: String, _ query: String) -> Int {
            store.affinities(query: query)[itemKey] ?? 0
        }

        func globalAffinity(_ store: LauncherRankingStore, _ itemKey: String) -> Int {
            store.globalAffinities()[itemKey] ?? 0
        }

        let whatsApp = "net.whatsapp.WhatsApp"
        let wick = "com.example.wick"
        let cafe = "com.example.cafe"

        check(
            "query key trims surrounding whitespace",
            LauncherRankingStore.normalize(" wha \n") == "wha")
        check("query key folds case", LauncherRankingStore.normalize("WhA") == "wha")
        check("query key folds diacritics", LauncherRankingStore.normalize("Café") == "cafe")
        check(
            "query key is locale-independent",
            LauncherRankingStore.normalize("I") == "i"
                && LauncherRankingStore.normalize("I")
                    != "I".folding(
                        options: [.caseInsensitive, .diacriticInsensitive],
                        locale: Locale(identifier: "tr_TR"))
        )

        check("unvisited result has no query affinity", affinity(store, whatsApp, "w") == 0)
        check("unvisited result has no global affinity", globalAffinity(store, whatsApp) == 0)

        store.record(itemKey: cafe, query: " Café ")
        check("normalized query recalls learned choice", affinity(store, cafe, "cafe") > 0)

        store.record(itemKey: whatsApp, query: "Wha")
        check("visit teaches first query prefix", affinity(store, whatsApp, "w") == 1_000)
        check("visit teaches full normalized query", affinity(store, whatsApp, "WHA") == 1_000)
        check("visit does not teach a different query", affinity(store, whatsApp, "wa") == 0)
        check("typed visit also teaches global usage", globalAffinity(store, whatsApp) == 1_000)

        store.record(itemKey: whatsApp, query: "Wha")
        check("two recent visits score 1900", affinity(store, whatsApp, "w") == 1_900)
        store.record(itemKey: whatsApp, query: "Wha")
        check("three recent visits score 2710", affinity(store, whatsApp, "w") == 2_710)
        for _ in 0..<4 { store.record(itemKey: whatsApp, query: "Wha") }
        check("repeated visits rise with diminishing returns", affinity(store, whatsApp, "w") == 5_217)

        clock.addTimeInterval(30 * 86_400)
        check("query evidence has a 30-day half-life", affinity(store, whatsApp, "w") == 2_609)
        check("global evidence decays more gently", globalAffinity(store, whatsApp) == 3_689)
        clock.addTimeInterval(30 * 86_400)
        check("stale query evidence keeps decaying", affinity(store, whatsApp, "w") == 1_304)
        check("global evidence has a 60-day half-life", globalAffinity(store, whatsApp) == 2_609)

        store.record(itemKey: wick, query: "")
        check("empty-query launch teaches global usage", globalAffinity(store, wick) == 1_000)
        check("empty-query launch creates no query association", affinity(store, wick, "w") == 0)

        store.resetAll()
        for _ in 0..<50 { store.record(itemKey: whatsApp, query: "w") }
        clock.addTimeInterval(60 * 86_400)
        let oldHabit = affinity(store, whatsApp, "w")
        store.record(itemKey: wick, query: "w")
        store.record(itemKey: wick, query: "w")
        store.record(itemKey: wick, query: "w")
        check("three recent choices overtake a stale saturated habit", affinity(store, wick, "w") > oldHabit)

        let table = store.affinities(query: "w")
        check("one pass returns every item learned for the query", Set(table.keys) == [whatsApp, wick])

        let persistedWickAffinity = affinity(store, wick, "w")
        await store.flush()
        let reloaded = LauncherRankingStore(fileURL: fileURL) { clock }
        check(
            "records persist across store instances",
            affinity(reloaded, wick, "w") == persistedWickAffinity)

        reloaded.reset(itemKey: whatsApp)
        check("per-item reset clears query and global history", !reloaded.hasRanking(for: whatsApp))
        check("per-item reset preserves other items", reloaded.hasRanking(for: wick))

        reloaded.resetAll()
        check("global reset clears all learned ranking", reloaded.isEmpty)
        await reloaded.flush()

        print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
        exit(failures == 0 ? 0 : 1)
    }
}
