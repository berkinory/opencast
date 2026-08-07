import Foundation

struct SettingsSearchRecord: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let detail: String
    let breadcrumb: String
    let keywords: [String]
}

struct SettingsSearchMatch: Equatable, Sendable {
    let record: SettingsSearchRecord
    let score: Int
}

enum SettingsSearchIndex {
    static func search(
        _ query: String,
        in records: [SettingsSearchRecord],
        limit: Int = 40
    ) -> [SettingsSearchMatch] {
        let normalizedQuery = normalize(query)
        let queryTokens = words(in: normalizedQuery)
        guard !queryTokens.isEmpty, limit > 0 else { return [] }

        return records.compactMap { record in
            score(record, query: normalizedQuery, tokens: queryTokens).map {
                SettingsSearchMatch(record: record, score: $0)
            }
        }
        .sorted {
            if $0.score != $1.score { return $0.score > $1.score }
            return $0.record.title.localizedCaseInsensitiveCompare($1.record.title)
                == .orderedAscending
        }
        .prefix(limit)
        .map { $0 }
    }

    private static func score(
        _ record: SettingsSearchRecord,
        query: String,
        tokens: [String]
    ) -> Int? {
        let title = normalize(record.title)
        let breadcrumb = normalize(record.breadcrumb)
        let detail = normalize(record.detail)
        let keywords = normalize(record.keywords.joined(separator: " "))
        let fields = [
            SearchField(text: title, weight: 10),
            SearchField(text: breadcrumb, weight: 5),
            SearchField(text: keywords, weight: 4),
            SearchField(text: detail, weight: 2),
        ]

        var total = 0
        for token in tokens {
            guard let best = fields.compactMap({ tokenScore(token, in: $0) }).max() else {
                return nil
            }
            total += best
        }

        if title == query {
            total += 100_000
        } else if title.hasPrefix(query) {
            total += 35_000
        } else if title.contains(query) {
            total += 20_000
        } else if keywords.contains(query) {
            total += 8_000
        } else if detail.contains(query) || breadcrumb.contains(query) {
            total += 4_000
        }
        return total
    }

    private static func tokenScore(_ token: String, in field: SearchField) -> Int? {
        if field.text == token { return 9_000 * field.weight }
        let fieldWords = words(in: field.text)
        if fieldWords.contains(token) { return 7_000 * field.weight }
        if fieldWords.contains(where: { $0.hasPrefix(token) }) { return 5_000 * field.weight }
        if field.text.contains(token) { return 3_000 * field.weight }

        guard token.count >= 4 else { return nil }
        let allowedDistance = token.count >= 8 ? 2 : 1
        if fieldWords.contains(where: { editDistance(token, $0, limit: allowedDistance) <= allowedDistance }) {
            return 500 * field.weight
        }
        return nil
    }

    private static func normalize(_ text: String) -> String {
        let folded = text.folding(
            options: [.caseInsensitive, .diacriticInsensitive],
            locale: Locale.current
        )
        let separated = folded.map { character in
            character.isLetter || character.isNumber ? character : " "
        }
        return String(separated).split(whereSeparator: \Character.isWhitespace).joined(separator: " ")
    }

    private static func words(in text: String) -> [String] {
        text.split(separator: " ").map(String.init)
    }

    private static func editDistance(_ lhs: String, _ rhs: String, limit: Int) -> Int {
        let left = Array(lhs)
        let right = Array(rhs)
        if abs(left.count - right.count) > limit { return limit + 1 }

        var previous = Array(0...right.count)
        for (leftIndex, leftCharacter) in left.enumerated() {
            var current = [leftIndex + 1]
            var rowMinimum = current[0]
            for (rightIndex, rightCharacter) in right.enumerated() {
                let insertion = current[rightIndex] + 1
                let deletion = previous[rightIndex + 1] + 1
                let substitution = previous[rightIndex] + (leftCharacter == rightCharacter ? 0 : 1)
                let value = min(insertion, deletion, substitution)
                current.append(value)
                rowMinimum = min(rowMinimum, value)
            }
            if rowMinimum > limit { return limit + 1 }
            previous = current
        }
        return previous[right.count]
    }

    private struct SearchField {
        let text: String
        let weight: Int
    }
}
