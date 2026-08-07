// Standalone test for launcher matching and adaptive ordering (run: swift Tools/fuzz-test.swift); keep FuzzyMatch in sync with Opencast/Features/Launcher/AppIndex.swift.

import Foundation

enum FuzzyMatch {
    enum Kind: Int, Sendable {
        case subsequence
        case substring
        case wordStart
        case prefix
        case exact
    }

    struct Result: Sendable {
        let kind: Kind
        let detailScore: Int
        let isAlias: Bool

        init(kind: Kind, detailScore: Int, isAlias: Bool = false) {
            self.kind = kind
            self.detailScore = detailScore
            self.isAlias = isAlias
        }

        var score: Int {
            switch kind {
            case .exact: return 100_000
            case .prefix: return 90_000 + detailScore
            case .wordStart: return 80_000 + detailScore
            case .substring: return 70_000 + detailScore
            case .subsequence: return detailScore
            }
        }
    }

    static func score(query: String, candidate: String) -> Int? {
        let q = normalized(query)
        guard !q.isEmpty else { return 0 }
        return match(normalizedQuery: q, candidate: normalized(candidate))?.score
    }

    static func match(query: String, candidate: String) -> Result? {
        match(query: query, candidate: candidate, aliases: [])
    }

    static func match(
        query: String, candidate: String, aliases: [String], preferAlias: Bool = false
    ) -> Result? {
        let q = normalized(query)
        guard !q.isEmpty else { return nil }
        let literal = match(normalizedQuery: q, candidate: normalized(candidate))
        let aliasMatches = aliases.compactMap {
            match(normalizedQuery: q, candidate: normalized($0)).map {
                Result(kind: $0.kind, detailScore: $0.detailScore, isAlias: true)
            }
        }
        let alias = aliasMatches.max { left, right in
            if left.kind != right.kind { return left.kind.rawValue < right.kind.rawValue }
            return left.detailScore < right.detailScore
        }
        guard preferAlias else { return literal ?? alias }
        return ((literal.map { [$0] } ?? []) + aliasMatches).max { left, right in
            if left.kind != right.kind { return left.kind.rawValue < right.kind.rawValue }
            return left.detailScore < right.detailScore
        }
    }

    private static func match(normalizedQuery q: String, candidate c: String) -> Result? {
        if c == q { return Result(kind: .exact, detailScore: 0) }
        if c.hasPrefix(q) { return Result(kind: .prefix, detailScore: -c.count) }

        if let range = c.range(of: q) {
            let kind: Kind = isWordStart(c, range.lowerBound) ? .wordStart : .substring
            return Result(kind: kind, detailScore: -c.count)
        }

        guard let score = subsequenceScore(Array(q), Array(c)) else { return nil }
        return Result(kind: .subsequence, detailScore: score)
    }

    private static func normalized(_ value: String) -> String {
        let scalars = value.unicodeScalars.filter {
            $0.properties.generalCategory != .format
        }
        return String(String.UnicodeScalarView(scalars)).lowercased()
    }

    private static func isWordStart(_ s: String, _ index: String.Index) -> Bool {
        if index == s.startIndex { return true }
        let before = s[s.index(before: index)]
        return !before.isLetter && !before.isNumber
    }

    private static func subsequenceScore(_ q: [Character], _ c: [Character]) -> Int? {
        var qi = 0
        var score = 0
        var run = 0
        var prev = -2
        for (ci, ch) in c.enumerated() where qi < q.count && ch == q[qi] {
            var bonus = 1
            if ci == prev + 1 {
                run += 1
                bonus += run * 3
            } else {
                run = 0
            }
            if ci == 0 {
                bonus += 12
            } else {
                let before = c[ci - 1]
                if !before.isLetter && !before.isNumber { bonus += 8 }
            }
            score += bonus
            prev = ci
            qi += 1
        }
        guard qi == q.count else { return nil }
        return score
    }
}

let apps: [(name: String, aliases: [String])] = [
    ("Google Chrome", []), ("Chess", []), ("Time Machine", []), ("Safari", []),
    ("Bluetooth File Exchange", []), ("Screenshot", []), ("Screen Sharing", []),
    ("Visual Studio Code", []), ("Photos", []), ("App Store", []),
    ("System Settings", []), ("Calendar", []), ("Terminal", []), ("WhatsApp", []),
    ("Wick", []),
]

func promotedTier(_ kind: FuzzyMatch.Kind, affinity: Int) -> Int {
    guard affinity >= 2_500 else { return kind.rawValue }
    switch kind {
    case .substring, .wordStart: return kind.rawValue + 1
    case .subsequence, .prefix, .exact: return kind.rawValue
    }
}

func rank(
    _ query: String, affinities: [String: Int] = [:], globalAffinities: [String: Int] = [:]
) -> [String] {
    apps.compactMap { app -> (name: String, tier: Int, detail: Int, affinity: Int, global: Int)? in
        guard
            let match = FuzzyMatch.match(
                query: query, candidate: app.name, aliases: app.aliases
            )
        else { return nil }
        let affinity = affinities[app.name, default: 0]
        let global = globalAffinities[app.name, default: 0]
        let detail = match.detailScore + affinity / 100 + min(4, global / 2_500)
        let tier =
            match.isAlias
            ? match.kind.rawValue - 5
            : promotedTier(match.kind, affinity: affinity)
        return (app.name, tier, detail, affinity, global)
    }
    .sorted {
        if $0.tier != $1.tier { return $0.tier > $1.tier }
        if $0.detail != $1.detail { return $0.detail > $1.detail }
        if $0.affinity != $1.affinity { return $0.affinity > $1.affinity }
        if $0.global != $1.global { return $0.global > $1.global }
        return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
    }
    .map(\.name)
}

var failures = 0
@MainActor
func check(_ description: String, _ condition: Bool, _ detail: String = "") {
    if condition {
        print("PASS  \(description)")
    } else {
        print("FAIL  \(description)  \(detail)")
        failures += 1
    }
}

let chrome = rank("chrome")
check("'chrome' top is Google Chrome", chrome.first == "Google Chrome", "got \(chrome)")
check("'chrome' does not include Chess", !chrome.contains("Chess"), "got \(chrome)")

let ch = rank("ch")
check("'ch' includes Google Chrome", ch.contains("Google Chrome"), "got \(ch)")
check("'ch' includes Chess", ch.contains("Chess"))
check("prefix beats word-start by default", ch.first == "Chess", "got \(ch)")
check(
    "one visit cannot cross a fuzzy tier",
    rank("ch", affinities: ["Google Chrome": 1_000]).first == "Chess")
let learnedChrome = rank("ch", affinities: ["Google Chrome": 2_710])
check(
    "three recent visits promote Chrome over Chess by one tier",
    learnedChrome.first == "Google Chrome", "got \(learnedChrome)")
check(
    "exact title remains absolute after learning",
    rank("chess", affinities: ["Google Chrome": 10_000]).first == "Chess")

check("'saf' top is Safari", rank("saf").first == "Safari", "got \(rank("saf"))")
check("'tm' includes Time Machine", rank("tm").contains("Time Machine"), "got \(rank("tm"))")
check(
    "'code' includes Visual Studio Code", rank("code").contains("Visual Studio Code"),
    "got \(rank("code"))")
check("'terminal' exact top", rank("terminal").first == "Terminal")
check("'xyz' matches nothing", rank("xyz").isEmpty, "got \(rank("xyz"))")

let defaultW = rank("w")
check("shorter Wick wins the default prefix tie", defaultW.first == "Wick", "got \(defaultW)")
let learnedW = rank("w", affinities: ["WhatsApp": 1_000])
check("query learning reorders results within a tier", learnedW.first == "WhatsApp")

let xunleiAliases = Romanization.aliases(for: "迅雷")
check("'xunlei' generates a full romanization alias", xunleiAliases.contains("xunlei"))
check("'xl' generates initials", xunleiAliases.contains("xl"))
let qsyyAliases = Romanization.aliases(for: "汽水音乐")
check("polyphone-aware initials use 'qsyy'", qsyyAliases.contains("qsyy"))
check("polyphone-aware full reading uses 'qishuiyinyue'", qsyyAliases.contains("qishuiyinyue"))
check(
    "romanized exact stays below a literal subsequence",
    FuzzyMatch.match(query: "gc", candidate: "Google Chrome", aliases: ["gc"])?.isAlias == false
)
check(
    "command alias exact beats its embedded literal",
    FuzzyMatch.match(
        query: "caffeinate", candidate: "Decaffeinate", aliases: ["Caffeinate"], preferAlias: true
    )?.isAlias == true
)

let gc = FuzzyMatch.match(query: "gc", candidate: "Google Chrome")
check("'gc' is a subsequence match", gc?.kind == .subsequence)
check(
    "subsequence learning never grants a tier promotion",
    promotedTier(.subsequence, affinity: 10_000) == FuzzyMatch.Kind.subsequence.rawValue)
check(
    "global usage never grants a tier promotion",
    rank("ch", globalAffinities: ["Google Chrome": 10_000]).first == "Chess")

let markedWhatsApp = "\u{200E}WhatsApp"
check(
    "invisible format mark does not demote WhatsApp's prefix match",
    FuzzyMatch.score(query: "w", candidate: markedWhatsApp)
        == FuzzyMatch.score(query: "w", candidate: "WhatsApp"))

print(failures == 0 ? "\nALL PASSED" : "\n\(failures) FAILED")
exit(failures == 0 ? 0 : 1)
