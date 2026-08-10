import AppKit
import Combine

enum UninstallSort: String, CaseIterable, Sendable {
    case path
    case size
    case name

    var title: String {
        switch self {
        case .path: return "Sort by Path"
        case .size: return "Sort by Size"
        case .name: return "Sort by Name"
        }
    }

    var systemImage: String {
        switch self {
        case .path: return "folder"
        case .size: return "externaldrive"
        case .name: return "textformat"
        }
    }
}

struct UninstallOutcome: Equatable, Sendable {
    let removedCount: Int
    let reclaimed: Int64
    let failures: [LeftoverItem]
    let permanently: Bool
}

enum UninstallPhase: Equatable, Sendable {
    case selecting
    case removing(permanently: Bool)
    case done(UninstallOutcome)
}

@MainActor
final class UninstallSession: ObservableObject {
    @Published private(set) var target: AppEntry?
    @Published private(set) var items: [LeftoverItem] = []
    @Published private(set) var sort: UninstallSort = .path
    @Published private(set) var isScanning = false
    @Published private(set) var checked: Set<String> = []
    @Published private(set) var phase: UninstallPhase = .selecting

    private var scanToken = UUID()

    var checkedItems: [LeftoverItem] { items.filter { checked.contains($0.id) } }
    var checkedSize: Int64 { checkedItems.reduce(0) { $0 + ($1.size ?? 0) } }

    func isChecked(_ item: LeftoverItem) -> Bool { checked.contains(item.id) }

    func filtered(_ query: String) -> [LeftoverItem] {
        let needle = query.trimmingCharacters(in: .whitespaces).lowercased()
        guard !needle.isEmpty else { return items }
        return items.filter {
            $0.url.lastPathComponent.lowercased().contains(needle)
                || $0.displayPath.lowercased().contains(needle)
        }
    }

    func setSort(_ sort: UninstallSort) {
        guard sort != self.sort else { return }
        self.sort = sort
        items = Self.sorted(items, by: sort)
    }

    private static func sorted(_ items: [LeftoverItem], by sort: UninstallSort) -> [LeftoverItem] {
        switch sort {
        case .path:
            return items.sorted { $0.url.path.localizedStandardCompare($1.url.path) == .orderedAscending }
        case .name:
            return items.sorted {
                $0.url.lastPathComponent.localizedStandardCompare($1.url.lastPathComponent) == .orderedAscending
            }
        case .size:
            return items.sorted { ($0.size ?? -1) > ($1.size ?? -1) }
        }
    }

    func begin(app: AppEntry) {
        let token = UUID()
        scanToken = token
        target = app
        items = []
        checked = []
        phase = .selecting
        isScanning = true

        let name = app.name
        let bundleID = app.bundleID
        let url = app.url.resolvingSymlinksInPath()
        let link = url == app.url ? nil : app.url
        let hasSibling = Self.hasSiblingInstall(bundleID: bundleID, excluding: [app.url, url])
        let home = FileManager.default.homeDirectoryForCurrentUser

        Task { [weak self] in
            let discovered = await Task.detached(priority: .userInitiated) { () -> [LeftoverItem] in
                var found = [LeftoverItem(url: url, kind: .bundle, size: nil)]
                if let link { found.append(LeftoverItem(url: link, kind: .bundle, size: nil)) }
                found += AppLeftovers.supportPaths(
                    appName: name, bundleID: bundleID, home: home, siblingBundleExists: hasSibling
                ).map { LeftoverItem(url: $0, kind: .support, size: nil) }
                return found
            }.value
            guard let self, scanToken == token else { return }
            items = Self.sorted(discovered, by: sort)
            checked = Set(discovered.map(\.id))
            isScanning = false
            await measureSizes(token: token)
        }
    }

    private func measureSizes(token: UUID) async {
        let pending = items.filter { $0.size == nil }
        await withTaskGroup(of: (String, Int64?).self) { group in
            for item in pending {
                group.addTask {
                    guard !Task.isCancelled else { return (item.id, nil) }
                    return (item.id, AppLeftovers.size(of: item.url))
                }
            }
            for await (id, size) in group {
                guard !Task.isCancelled, scanToken == token else {
                    group.cancelAll()
                    return
                }
                guard let size, let index = items.firstIndex(where: { $0.id == id }) else {
                    continue
                }
                let item = items[index]
                items[index] = LeftoverItem(url: item.url, kind: item.kind, size: size)
            }
        }
        guard !Task.isCancelled, scanToken == token else { return }
        if sort == .size { items = Self.sorted(items, by: .size) }
    }

    func end() {
        scanToken = UUID()
        target = nil
        items = []
        checked = []
        isScanning = false
        phase = .selecting
    }

    func toggle(_ item: LeftoverItem) {
        if checked.contains(item.id) {
            checked.remove(item.id)
        } else {
            checked.insert(item.id)
        }
    }

    @discardableResult
    func remove(permanently: Bool = false) async -> UninstallOutcome {
        guard phase == .selecting else {
            return UninstallOutcome(removedCount: 0, reclaimed: 0, failures: [], permanently: permanently)
        }
        phase = .removing(permanently: permanently)
        let targets = checkedItems
        if targets.contains(where: { $0.kind == .bundle }), let bundleID = target?.bundleID {
            await Self.quitAndWait(bundleID: bundleID)
        }
        let failedPaths = await Task.detached(priority: .userInitiated) {
            AppLeftovers.remove(targets.map(\.url), permanently: permanently)
        }.value
        let failures = targets.filter { failedPaths.contains($0.url.path) }
        let removed = targets.filter { !failedPaths.contains($0.url.path) }
        let outcome = UninstallOutcome(
            removedCount: removed.count,
            reclaimed: removed.reduce(0) { $0 + ($1.size ?? 0) },
            failures: failures,
            permanently: permanently
        )
        phase = .done(outcome)
        return outcome
    }

    private static func hasSiblingInstall(bundleID: String?, excluding urls: [URL]) -> Bool {
        guard let bundleID else { return false }
        let own = Set(urls.flatMap { [$0.standardizedFileURL.path, $0.resolvingSymlinksInPath().path] })
        return NSWorkspace.shared.urlsForApplications(withBundleIdentifier: bundleID).contains {
            !own.contains($0.standardizedFileURL.path)
                && !own.contains($0.resolvingSymlinksInPath().path)
        }
    }

    private static func quitAndWait(bundleID: String) async {
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        for _ in 0..<30 {
            if NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).isEmpty { return }
            try? await Task.sleep(for: .milliseconds(100))
        }
    }
}
