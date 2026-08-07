import Foundation

struct Snippet: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var content: String
    var keyword: String
    var icon: String
    let createdAt: Date
    var modifiedAt: Date
    var pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    init(
        id: UUID = UUID(), name: String, content: String, keyword: String = "",
        icon: String = "doc.text", createdAt: Date = Date(), modifiedAt: Date? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.content = content
        self.keyword = keyword
        self.icon = icon
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.pinnedAt = pinnedAt
    }
}

enum SnippetValidationError: LocalizedError, Equatable {
    case emptyName
    case emptyContent
    case invalidKeyword
    case duplicateKeyword

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Add a name for the snippet."
        case .emptyContent: return "Add some text to the snippet."
        case .invalidKeyword: return "Keywords cannot contain spaces, quotes, or new lines."
        case .duplicateKeyword: return "That keyword is already used by another snippet."
        }
    }
}

@MainActor
final class SnippetStore: ObservableObject {
    @Published private(set) var snippets: [Snippet] = []

    let fileURL: URL

    init(fileURL: URL = SnippetStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func search(_ query: String) -> [Snippet] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ordered(snippets) }

        let matched =
            snippets
            .compactMap { snippet -> (Snippet, Int)? in
                let scores = [snippet.name, snippet.keyword, snippet.content].compactMap {
                    FuzzyMatch.score(query: query, candidate: $0)
                }
                guard let score = scores.max() else { return nil }
                return (snippet, score)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.modifiedAt > $1.0.modifiedAt
            }
            .map(\.0)
        return ordered(matched)
    }

    func togglePinned(_ snippet: Snippet) throws {
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return }
        let previous = snippets
        snippets[index].pinnedAt = snippets[index].isPinned ? nil : Date()
        do {
            try persist()
        } catch {
            snippets = previous
            throw error
        }
    }

    func rowIndex(of snippet: Snippet, in query: String) -> Int? {
        search(query).firstIndex { $0.id == snippet.id }
    }

    @discardableResult
    func create(name: String, content: String, keyword: String, icon: String) throws -> Snippet {
        let snippet = Snippet(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            content: content,
            keyword: keyword.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon
        )
        try validate(snippet)
        let previous = snippets
        snippets.insert(snippet, at: 0)
        do {
            try persist()
        } catch {
            snippets = previous
            throw error
        }
        return snippet
    }

    @discardableResult
    func update(_ snippet: Snippet) throws -> Snippet {
        var updated = snippet
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.keyword = updated.keyword.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.modifiedAt = Date()
        try validate(updated, excluding: snippet.id)
        guard let index = snippets.firstIndex(where: { $0.id == snippet.id }) else { return updated }
        let previous = snippets
        snippets[index] = updated
        snippets.sort { $0.modifiedAt > $1.modifiedAt }
        do {
            try persist()
        } catch {
            snippets = previous
            throw error
        }
        return updated
    }

    @discardableResult
    func duplicate(_ snippet: Snippet) throws -> Snippet {
        try create(
            name: "\(snippet.name) Copy",
            content: snippet.content,
            keyword: "",
            icon: snippet.icon
        )
    }

    func delete(_ snippet: Snippet) throws {
        let previous = snippets
        snippets.removeAll { $0.id == snippet.id }
        guard snippets != previous else { return }
        do {
            try persist()
        } catch {
            snippets = previous
            throw error
        }
    }

    func snippet(for id: Snippet.ID?) -> Snippet? {
        guard let id else { return nil }
        return snippets.first { $0.id == id }
    }

    private func validate(_ snippet: Snippet, excluding id: Snippet.ID? = nil) throws {
        guard !snippet.name.isEmpty else { throw SnippetValidationError.emptyName }
        guard !snippet.content.isEmpty else { throw SnippetValidationError.emptyContent }
        if !snippet.keyword.isEmpty {
            guard !snippet.keyword.contains(where: { $0.isWhitespace || $0 == "\"" || $0 == "'" }) else {
                throw SnippetValidationError.invalidKeyword
            }
            let duplicate = snippets.contains {
                $0.id != id && !$0.keyword.isEmpty
                    && $0.keyword.caseInsensitiveCompare(snippet.keyword) == .orderedSame
            }
            guard !duplicate else { throw SnippetValidationError.duplicateKeyword }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([Snippet].self, from: data)
        else { return }
        snippets = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(snippets)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ordered(_ values: [Snippet]) -> [Snippet] {
        let pinned = values.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture)
        }
        return pinned + values.filter { !$0.isPinned }
    }

    private static var defaultFileURL: URL {
        AppPaths.applicationSupport()
            .appendingPathComponent("snippets.json")
    }
}
