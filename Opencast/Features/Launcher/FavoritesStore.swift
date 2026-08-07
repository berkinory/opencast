import Foundation

/// Persists favorite launcher entries as ordered keys, pinned to the top of the launcher when the search is empty.
@MainActor
final class FavoritesStore: ObservableObject {
    private let defaults = UserDefaults.standard
    private let key = "favoriteApps"
    private let quicklinkKey = "favoriteQuicklinks"

    @Published private(set) var keys: [String]
    @Published private(set) var quicklinkKeys: [String]
    private(set) var revision = 0

    init() {
        keys = defaults.stringArray(forKey: key) ?? []
        quicklinkKeys = defaults.stringArray(forKey: quicklinkKey) ?? []
    }

    func key(for app: AppEntry) -> String { app.preferenceKey }

    func isFavorite(_ app: AppEntry) -> Bool { keys.contains(key(for: app)) }

    /// Replace the whole favorites list at once (used when importing a settings backup).
    func replace(keys newKeys: [String]) {
        guard keys != newKeys else { return }
        keys = newKeys
        revision &+= 1
        defaults.set(keys, forKey: key)
    }

    func toggle(_ app: AppEntry) {
        let k = key(for: app)
        if let index = keys.firstIndex(of: k) {
            keys.remove(at: index)
        } else {
            keys.append(k)
        }
        revision &+= 1
        defaults.set(keys, forKey: key)
    }

    func isFavorite(_ quicklink: Quicklink) -> Bool {
        quicklinkKeys.contains(quicklink.id.uuidString)
    }

    func toggle(_ quicklink: Quicklink) {
        let id = quicklink.id.uuidString
        if let index = quicklinkKeys.firstIndex(of: id) {
            quicklinkKeys.remove(at: index)
        } else {
            quicklinkKeys.append(id)
        }
        revision &+= 1
        defaults.set(quicklinkKeys, forKey: quicklinkKey)
    }

    func remove(_ quicklink: Quicklink) {
        guard let index = quicklinkKeys.firstIndex(of: quicklink.id.uuidString) else { return }
        quicklinkKeys.remove(at: index)
        revision &+= 1
        defaults.set(quicklinkKeys, forKey: quicklinkKey)
    }

    /// Split `apps` into favorites (in stored order) and the rest (order preserved).
    func ordered(_ apps: [AppEntry]) -> (favorites: [AppEntry], rest: [AppEntry]) {
        guard !keys.isEmpty else { return ([], apps) }
        let byKey = Dictionary(
            apps.map { (key(for: $0), $0) }, uniquingKeysWith: { first, _ in first })
        let favorites = keys.compactMap { byKey[$0] }
        let favoriteKeys = Set(keys)
        let rest = apps.filter { !favoriteKeys.contains(key(for: $0)) }
        return (favorites, rest)
    }

    func ordered(_ quicklinks: [Quicklink]) -> (favorites: [Quicklink], rest: [Quicklink]) {
        guard !quicklinkKeys.isEmpty else { return ([], quicklinks) }
        let byID = Dictionary(
            quicklinks.map { ($0.id.uuidString, $0) }, uniquingKeysWith: { first, _ in first })
        let favorites = quicklinkKeys.compactMap { byID[$0] }
        let favoriteIDs = Set(quicklinkKeys)
        let rest = quicklinks.filter { !favoriteIDs.contains($0.id.uuidString) }
        return (favorites, rest)
    }
}
