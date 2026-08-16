import AppKit
import Combine
import CoreServices

struct AppEntry: Identifiable, Hashable, Sendable {
    enum Kind: String, Sendable {
        case application
        case systemSettings
        case command
    }

    let id: String  // file path (or "command:…" id) — always unique
    let name: String  // clean display name, never includes ".app"
    let url: URL
    let bundleID: String?
    let kind: Kind
    let searchAliases: [String]

    init(
        id: String,
        name: String,
        url: URL,
        bundleID: String?,
        kind: Kind,
        searchAliases: [String] = []
    ) {
        self.id = id
        self.name = name
        self.url = url
        self.bundleID = bundleID
        self.kind = kind
        self.searchAliases = searchAliases
    }

    /// Stable identity for learned ranking, favorites, and other per-entry preferences.
    var preferenceKey: String { bundleID ?? id }

    var kindLabel: String {
        switch kind {
        case .application: return "Application"
        case .systemSettings: return "System Setting"
        case .command:
            if WindowCommandCatalog.command(forEntryID: id) != nil { return "Window Command" }
            if SystemCommandCatalog.command(forEntryID: id) != nil { return "System Command" }
            return "Command"
        }
    }

    var primaryActionTitle: String {
        switch kind {
        case .application:
            return "Open Application"
        case .systemSettings:
            return "Open System Setting"
        case .command:
            if WindowCommandCatalog.command(forEntryID: id) != nil { return "Move Window" }
            if SystemCommandCatalog.command(forEntryID: id) != nil { return "Run Command" }
            return CommandRegistry.command(for: self)?.primaryActionTitle ?? "Open Command"
        }
    }

    /// The global-hotkey action that opens this entry.
    var hotKeyAction: HotKeyAction? {
        switch kind {
        case .application:
            return bundleID.map(HotKeyAction.app)
        case .systemSettings:
            return bundleID.map(HotKeyAction.settingsPane)
        case .command:
            if let command = CommandRegistry.command(for: self), let action = command.hotKeyAction {
                return action
            }
            if let command = WindowCommandCatalog.command(forEntryID: id) {
                return .windowCommand(id: command.id)
            }
            return .command(id: id)
        }
    }

    /// Synthetic command entries expose an SF Symbol name; row renderers apply the shared feature-icon surface. Everything else uses its file icon.
    var isSymbolIcon: Bool { kind == .command }
    var symbolIconName: String {
        return SystemCommandCatalog.command(forEntryID: id)?.sfSymbol
            ?? CommandRegistry.command(for: self)?.sfSymbol
            ?? WindowCommandCatalog.command(forEntryID: id)?.sfSymbol
            ?? "questionmark"
    }

    var icon: NSImage {
        isSymbolIcon
            ? IconCache.symbolIcon(named: symbolIconName) : IconCache.icon(forFile: url.path)
    }
}

/// Caches app icons by file path, downsampled to a small fixed bitmap and byte-bounded, so list rows don't re-hit `NSWorkspace` or balloon memory.
enum IconCache {
    /// `NSCache` is thread-safe but not `Sendable`, so a detached decode populating what the main actor reads needs the guarantee asserted once here.
    private final class Cache: NSCache<NSString, NSImage>, @unchecked Sendable {}

    // Rendered at 24pt, so a 48px bitmap provides a sharp 2× Retina asset without retaining oversized icons.
    private static let displayPoint: CGFloat = 24

    private static let cache: Cache = {
        let cache = Cache()
        cache.totalCostLimit = 12 * 1024 * 1024
        return cache
    }()

    /// Cache-only lookups (never decode) so a row can paint an already-warm icon on the same frame.
    private static func applicationPath(for path: String) -> String {
        let components = URL(fileURLWithPath: path).standardizedFileURL.pathComponents
        guard let index = components.lastIndex(where: { $0.hasSuffix(".app") }) else { return path }
        return NSString.path(withComponents: Array(components.prefix(index + 1)))
    }

    static func cached(forFile path: String) -> NSImage? {
        cache.object(forKey: applicationPath(for: path) as NSString)
    }

    /// A freshly-decoded, thereafter-immutable `NSImage` is safe to move across the actor boundary.
    private struct Decoded: @unchecked Sendable { let image: NSImage? }

    /// Return the decode directly (not a cache re-read) so an `NSCache` purge mid-decode can't strand a row on its placeholder. A missing path returns nil — not `NSWorkspace`'s broken-document icon — and never caches, so an uninstalled app can't leave a broken icon behind.
    static func loadAsync(forFile path: String) async -> NSImage? {
        if let cached = cached(forFile: path) { return cached }
        return await Task.detached(priority: .userInitiated) { () -> Decoded in
            guard FileManager.default.fileExists(atPath: path) else { return Decoded(image: nil) }
            return Decoded(image: icon(forFile: path))
        }.value.image
    }
    static func icon(forFile path: String) -> NSImage {
        let resolvedPath = applicationPath(for: path)
        let key = resolvedPath as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let (icon, cost) = downsampled(NSWorkspace.shared.icon(forFile: resolvedPath))
        cache.setObject(icon, forKey: key, cost: cost)
        return icon
    }

    static func symbolIcon(named name: String) -> NSImage {
        let key = "symbol:" + name as NSString
        if let cached = cache.object(forKey: key) { return cached }
        let icon =
            NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(size: NSSize(width: displayPoint, height: displayPoint))
        cache.setObject(icon, forKey: key, cost: Int(displayPoint * displayPoint * 4))
        return icon
    }

    /// Rasterize the multi-rep workspace icon into one 24pt bitmap, returning it and its decoded byte cost.
    private static func downsampled(_ source: NSImage) -> (NSImage, Int) {
        // Fixed 2× (not `NSScreen.main`, which is main-thread-only) so this can rasterize on a detached decode.
        let pixels = Int(displayPoint * 2)
        let fallbackCost = Int(displayPoint * displayPoint * 4)
        guard
            let rep = NSBitmapImageRep(
                bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels, bitsPerSample: 8,
                samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                bytesPerRow: 0, bitsPerPixel: 0)
        else { return (source, fallbackCost) }
        rep.size = NSSize(width: displayPoint, height: displayPoint)
        guard let ctx = NSGraphicsContext(bitmapImageRep: rep) else {
            return (source, fallbackCost)
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = ctx
        ctx.imageInterpolation = .high
        source.draw(in: NSRect(origin: .zero, size: rep.size))
        NSGraphicsContext.restoreGraphicsState()

        let image = NSImage(size: rep.size)
        image.addRepresentation(rep)
        return (image, rep.bytesPerRow * rep.pixelsHigh)
    }
}

@MainActor
final class AppIndex: ObservableObject {
    @Published private(set) var apps: [AppEntry] = []

    private struct MatchKey: Equatable {
        let query: String
        let limit: Int
        let entriesRevision: Int
        let rankingRevision: Int
    }

    private struct ResultsKey: Equatable {
        let query: String
        let entriesRevision: Int
        let rankingRevision: Int
        let visibilityRevision: Int
        let favoritesRevision: Int
    }

    private struct AppFingerprint: Equatable, Sendable {
        let path: String
        let modified: Date?
        let size: Int64?
    }

    private struct AppScanCache: Sendable {
        let scopes: [String]
        let fingerprint: [AppFingerprint]
        let apps: [AppEntry]
    }

    private struct ScanResult: Sendable {
        let entries: [AppEntry]
        let panesCache: SettingsPaneScanner.Cache?
        let appCache: AppScanCache
    }

    private struct FeatureAvailability: Sendable {
        let clipboard: Bool
        let snippets: Bool
        let quicklinks: Bool
        let emoji: Bool

        func includes(_ command: CommandID) -> Bool {
            switch command {
            case .clipboardHistory: return clipboard
            case .searchSnippets, .createSnippet: return snippets
            case .searchQuicklinks, .createQuicklink: return quicklinks
            case .searchEmoji: return emoji
            default: return true
            }
        }
    }

    private var matchMemo = Memo<MatchKey, [AppEntry]>()
    private var resultsMemo = Memo<ResultsKey, [AppEntry]>()
    private var entriesRevision = 0
    private var paneCache: SettingsPaneScanner.Cache?
    private var appCache: AppScanCache?

    private var isRefreshing = false
    private var refreshPending = false
    private var windowCommandsVisible = false
    private var caffeinationActive = false
    private let ranking: LauncherRankingStore
    private weak var settings: AppSettings?
    private var cancellables = Set<AnyCancellable>()

    init(ranking: LauncherRankingStore) {
        self.ranking = ranking
    }

    func start(settings: AppSettings) {
        self.settings = settings
        windowCommandsVisible = settings.windowManagementEnabled
        settings.$searchScopes
            .dropFirst()
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)
        settings.$windowManagementEnabled
            .dropFirst()
            .sink { [weak self] enabled in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.windowCommandsVisible = enabled
                    Task { await self.refresh() }
                }
            }
            .store(in: &cancellables)
        Publishers.MergeMany(
            settings.$clipboardEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$snippetsEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$quicklinksEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher(),
            settings.$emojiEnabled.dropFirst().map { _ in () }.eraseToAnyPublisher()
        )
        .sink { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                Task { await self.refresh() }
            }
        }
        .store(in: &cancellables)
    }

    func setCaffeinationActive(_ active: Bool) {
        guard caffeinationActive != active else { return }
        caffeinationActive = active
        entriesRevision &+= 1
    }

    /// Re-scan (called on every launcher open); overlapping scans collapse into one trailing scan and an unchanged result does no UI work.
    func refresh() async {
        guard !isRefreshing else {
            refreshPending = true
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        repeat {
            refreshPending = false
            let scopes = settings?.searchScopes ?? SearchScopes.defaults
            let includeWindowCommands = windowCommandsVisible
            let caffeinationActive = self.caffeinationActive
            let featureAvailability = FeatureAvailability(
                clipboard: settings?.clipboardEnabled ?? true,
                snippets: settings?.snippetsEnabled ?? true,
                quicklinks: settings?.quicklinksEnabled ?? true,
                emoji: settings?.emojiEnabled ?? true
            )
            let reusingPaneCache = paneCache
            let reusingAppCache = appCache
            let result = await Task.detached(priority: .utility) {
                AppIndex.scan(
                    scopes: scopes,
                    includeWindowCommands: includeWindowCommands,
                    caffeinationActive: caffeinationActive,
                    featureAvailability: featureAvailability,
                    paneCache: reusingPaneCache,
                    appCache: reusingAppCache)
            }.value
            paneCache = result.panesCache
            appCache = result.appCache
            guard result.entries != apps else { continue }
            apps = result.entries
            entriesRevision &+= 1
        } while refreshPending
    }

    nonisolated private static func scan(
        scopes: [String], includeWindowCommands: Bool, caffeinationActive: Bool,
        featureAvailability: FeatureAvailability,
        paneCache: SettingsPaneScanner.Cache?,
        appCache: AppScanCache?
    ) -> ScanResult {
        let appURLs = SearchScopes.appBundles(in: scopes)
        let fingerprint = appFingerprint(for: appURLs)
        let apps: [AppEntry]
        if let appCache, appCache.scopes == scopes, appCache.fingerprint == fingerprint {
            apps = appCache.apps
        } else {
            apps = scanApps(appURLs)
        }

        let systemCommands = SystemCommandCatalog.all.map { command in
            AppEntry(
                id: command.entryID,
                name: command.name,
                url: URL(string: "opencast://system-command/" + command.id.rawValue)!,
                bundleID: nil,
                kind: .command)
        }
        let windowCommands =
            includeWindowCommands
            ? WindowCommandCatalog.all.map { command in
                AppEntry(
                    id: command.entryID,
                    name: command.name,
                    url: URL(string: "opencast://window-command/" + command.id.rawValue)!,
                    bundleID: nil,
                    kind: .command)
            }
            : []
        let commands = (systemCommands + windowCommands).sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        let launcherCommands = CommandRegistry.all.compactMap { entry -> AppEntry? in
            guard let command = CommandRegistry.command(for: entry),
                featureAvailability.includes(command)
            else { return nil }
            switch command {
            case .caffeinate:
                guard caffeinationActive else { return entry }
                return AppEntry(
                    id: CommandID.decaffeinate.rawValue,
                    name: CommandID.decaffeinate.name,
                    url: entry.url,
                    bundleID: nil,
                    kind: .command,
                    searchAliases: [CommandID.caffeinate.name])
            case .decaffeinate:
                return nil
            default:
                return entry
            }
        }
        let (panes, updatedPaneCache) = SettingsPaneScanner.scan(cache: paneCache)
        let entries = apps + panes + commands + launcherCommands
        return ScanResult(
            entries: entries,
            panesCache: updatedPaneCache,
            appCache: AppScanCache(scopes: scopes, fingerprint: fingerprint, apps: apps))
    }

    private nonisolated static func scanApps(_ urls: [URL]) -> [AppEntry] {
        var seenBundleIDs = Set<String>()
        var result: [AppEntry] = []
        for url in urls {
            let bundle = Bundle(url: url)
            let bundleID = bundle?.bundleIdentifier
            // Dedup by bundle ID; the earliest scope wins.
            if let bundleID, !seenBundleIDs.insert(bundleID).inserted { continue }

            let name = appName(bundle: bundle, url: url)
            let aliases = Romanization.aliases(for: name) + alternateNames(for: url, displayName: name)
            result.append(
                AppEntry(
                    id: url.path, name: name, url: url, bundleID: bundleID,
                    kind: .application, searchAliases: aliases))
        }
        return result.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private nonisolated static func appFingerprint(for urls: [URL]) -> [AppFingerprint] {
        urls.map { url in
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            return AppFingerprint(
                path: url.path,
                modified: values?.contentModificationDate,
                size: values?.fileSize.map(Int64.init))
        }.sorted { $0.path < $1.path }
    }

    private nonisolated static func appName(bundle: Bundle?, url: URL) -> String {
        let candidates: [String?] = [
            bundle?.object(forInfoDictionaryKey: "CFBundleDisplayName") as? String,
            bundle?.object(forInfoDictionaryKey: "CFBundleName") as? String,
            url.deletingPathExtension().lastPathComponent,
        ]
        return candidates.compactMap { candidate -> String? in
            guard let candidate else { return nil }
            let trimmed = candidate.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? nil : trimmed
        }.first ?? url.deletingPathExtension().lastPathComponent
    }

    private nonisolated static func alternateNames(for url: URL, displayName: String) -> [String] {
        guard let item = MDItemCreateWithURL(nil, url as CFURL) else { return [] }
        guard let values = MDItemCopyAttribute(item, "kMDItemAlternateNames" as CFString) as? [String]
        else {
            return []
        }

        var seen = Set<String>()
        return values.compactMap { value in
            var name = value.trimmingCharacters(in: .whitespacesAndNewlines)
            if name.lowercased().hasSuffix(".app") {
                name.removeLast(4)
            }
            guard !name.isEmpty, name.caseInsensitiveCompare(displayName) != .orderedSame else {
                return nil
            }
            return seen.insert(name.lowercased()).inserted ? name : nil
        }
    }

    /// Ranked matches. Empty query returns the full alphabetical list.
    func matches(_ query: String, limit: Int = 200) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        guard !q.isEmpty else { return apps }
        let key = MatchKey(
            query: q, limit: limit, entriesRevision: entriesRevision, rankingRevision: ranking.revision)
        return matchMemo.value(for: key) { rank(q, limit: limit) }
    }

    func orderedResults(
        query: String, visibility: VisibilityStore, favorites: FavoritesStore
    ) -> [AppEntry] {
        let q = query.trimmingCharacters(in: .whitespaces)
        let key = ResultsKey(
            query: q, entriesRevision: entriesRevision, rankingRevision: ranking.revision,
            visibilityRevision: visibility.revision, favoritesRevision: favorites.revision)
        return resultsMemo.value(for: key) {
            let base = matches(q).filter(visibility.isVisible)
            guard q.isEmpty else { return base }
            let split = favorites.ordered(base)
            return split.favorites + split.rest
        }
    }

    private func rank(_ q: String, limit: Int) -> [AppEntry] {
        let learned = ranking.affinities(query: q)
        let global = ranking.globalAffinities()
        let scored = apps.compactMap { app -> RankedApp? in
            guard
                let match = FuzzyMatch.match(
                    query: q, candidate: app.name, aliases: app.searchAliases,
                    preferAlias: app.kind == .command
                )
            else { return nil }
            let affinity = learned[app.preferenceKey] ?? 0
            let globalAffinity = global[app.preferenceKey] ?? 0
            let promotedTier =
                match.isAlias && app.kind != .command
                ? match.kind.rawValue - 5
                : Self.promotedTier(for: match.kind, affinity: affinity)
            // Query learning can overcome small within-tier shape differences; global usage stays a tiny tie-break and can never change tiers.
            let adaptiveDetail =
                match.detailScore + affinity / 100 + min(4, globalAffinity / 2_500)
            return RankedApp(
                app: app, tier: promotedTier, detail: adaptiveDetail,
                affinity: affinity, globalAffinity: globalAffinity)
        }
        return
            scored
            .sorted {
                if $0.tier != $1.tier { return $0.tier > $1.tier }
                if $0.detail != $1.detail { return $0.detail > $1.detail }
                if $0.affinity != $1.affinity { return $0.affinity > $1.affinity }
                if $0.globalAffinity != $1.globalAffinity {
                    return $0.globalAffinity > $1.globalAffinity
                }
                return $0.app.name.localizedCaseInsensitiveCompare($1.app.name)
                    == .orderedAscending
            }
            .prefix(limit)
            .map(\.app)
    }

    private struct RankedApp {
        let app: AppEntry
        let tier: Int
        let detail: Int
        let affinity: Int
        let globalAffinity: Int
    }

    /// A repeated, recent query choice may cross one adjacent quality boundary. Exact matches stay absolute, prefixes cannot become exact, and weak subsequences never receive a tier promotion.
    private static func promotedTier(for kind: FuzzyMatch.Kind, affinity: Int) -> Int {
        guard affinity >= 2_500 else { return kind.rawValue }
        switch kind {
        case .substring, .wordStart:
            return kind.rawValue + 1
        case .subsequence, .prefix, .exact:
            return kind.rawValue
        }
    }
}

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
        /// Quality within a match kind. Ranking compares the kind separately so adaptive history can safely promote by one tier without inheriting the old artificial 10k walls.
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

    /// Tiered relevance score retained for callers and the standalone matcher harness.
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

    /// App metadata can contain invisible bidirectional/zero-width format scalars (WhatsApp's display name starts with U+200E); they must not demote an otherwise-visible prefix match.
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

    /// Subsequence match with bonuses for consecutive hits and word boundaries, or nil when `q` isn't a subsequence of `c`.
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
