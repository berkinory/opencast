import Foundation

struct Quicklink: Codable, Equatable, Identifiable, Sendable {
    let id: UUID
    var name: String
    var link: String
    var icon: String
    var openWithBundleID: String
    let createdAt: Date
    var modifiedAt: Date
    var pinnedAt: Date?

    var isPinned: Bool { pinnedAt != nil }

    init(
        id: UUID = UUID(), name: String, link: String, icon: String = "link",
        openWithBundleID: String, createdAt: Date = Date(), modifiedAt: Date? = nil,
        pinnedAt: Date? = nil
    ) {
        self.id = id
        self.name = name
        self.link = link
        self.icon = icon
        self.openWithBundleID = openWithBundleID
        self.createdAt = createdAt
        self.modifiedAt = modifiedAt ?? createdAt
        self.pinnedAt = pinnedAt
    }
}

enum QuicklinkValidationError: LocalizedError, Equatable {
    case emptyName
    case emptyLink
    case missingApplication

    var errorDescription: String? {
        switch self {
        case .emptyName: return "Add a name for the quicklink."
        case .emptyLink: return "Add a link for the quicklink."
        case .missingApplication: return "Choose an application to open the quicklink."
        }
    }
}

@MainActor
final class QuicklinkStore: ObservableObject {
    @Published private(set) var quicklinks: [Quicklink] = []

    let fileURL: URL

    init(fileURL: URL = QuicklinkStore.defaultFileURL) {
        self.fileURL = fileURL
        load()
    }

    func search(_ query: String) -> [Quicklink] {
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return ordered(quicklinks) }
        guard let matchQuery = FuzzyMatch.Query(query) else { return [] }

        let matched =
            quicklinks
            .compactMap { quicklink -> (Quicklink, Int)? in
                let scores = [quicklink.name].compactMap {
                    FuzzyMatch.score(query: matchQuery, candidate: $0)
                }
                guard let score = scores.max() else { return nil }
                return (quicklink, score)
            }
            .sorted {
                if $0.1 != $1.1 { return $0.1 > $1.1 }
                return $0.0.modifiedAt > $1.0.modifiedAt
            }
            .map(\.0)
        return ordered(matched)
    }

    func togglePinned(_ quicklink: Quicklink) throws {
        guard let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) else { return }
        let previous = quicklinks
        quicklinks[index].pinnedAt = quicklinks[index].isPinned ? nil : Date()
        do {
            try persist()
        } catch {
            quicklinks = previous
            throw error
        }
    }

    func rowIndex(of quicklink: Quicklink, in query: String) -> Int? {
        search(query).firstIndex { $0.id == quicklink.id }
    }

    @discardableResult
    func create(
        name: String, link: String, icon: String, openWithBundleID: String
    ) throws -> Quicklink {
        let quicklink = Quicklink(
            name: name.trimmingCharacters(in: .whitespacesAndNewlines),
            link: link.trimmingCharacters(in: .whitespacesAndNewlines),
            icon: icon,
            openWithBundleID: openWithBundleID
        )
        try validate(quicklink)
        let previous = quicklinks
        quicklinks.insert(quicklink, at: 0)
        do {
            try persist()
        } catch {
            quicklinks = previous
            throw error
        }
        return quicklink
    }

    @discardableResult
    func update(_ quicklink: Quicklink) throws -> Quicklink {
        var updated = quicklink
        updated.name = updated.name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.link = updated.link.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.modifiedAt = Date()
        try validate(updated)
        guard let index = quicklinks.firstIndex(where: { $0.id == quicklink.id }) else {
            return updated
        }
        let previous = quicklinks
        quicklinks[index] = updated
        quicklinks.sort { $0.modifiedAt > $1.modifiedAt }
        do {
            try persist()
        } catch {
            quicklinks = previous
            throw error
        }
        return updated
    }

    @discardableResult
    func duplicate(_ quicklink: Quicklink) throws -> Quicklink {
        try create(
            name: "\(quicklink.name) Copy",
            link: quicklink.link,
            icon: quicklink.icon,
            openWithBundleID: quicklink.openWithBundleID
        )
    }

    func delete(_ quicklink: Quicklink) throws {
        let previous = quicklinks
        quicklinks.removeAll { $0.id == quicklink.id }
        guard quicklinks != previous else { return }
        do {
            try persist()
        } catch {
            quicklinks = previous
            throw error
        }
    }

    func quicklink(for id: Quicklink.ID?) -> Quicklink? {
        guard let id else { return nil }
        return quicklinks.first { $0.id == id }
    }

    private func validate(_ quicklink: Quicklink) throws {
        guard !quicklink.name.isEmpty else { throw QuicklinkValidationError.emptyName }
        guard !quicklink.link.isEmpty else { throw QuicklinkValidationError.emptyLink }
        guard !quicklink.openWithBundleID.isEmpty else {
            throw QuicklinkValidationError.missingApplication
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
            let decoded = try? JSONDecoder().decode([Quicklink].self, from: data)
        else { return }
        quicklinks = decoded.sorted { $0.modifiedAt > $1.modifiedAt }
    }

    private func persist() throws {
        let directory = fileURL.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(quicklinks)
        try data.write(to: fileURL, options: .atomic)
    }

    private func ordered(_ values: [Quicklink]) -> [Quicklink] {
        let pinned = values.filter(\.isPinned).sorted {
            ($0.pinnedAt ?? .distantFuture) < ($1.pinnedAt ?? .distantFuture)
        }
        return pinned + values.filter { !$0.isPinned }
    }

    private static var defaultFileURL: URL {
        AppPaths.applicationSupport()
            .appendingPathComponent("quicklinks.json")
    }
}
