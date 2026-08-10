import Foundation

struct LeftoverItem: Identifiable, Hashable, Sendable {
    enum Kind: Int, Sendable {
        case bundle
        case support
    }

    let url: URL
    let kind: Kind
    let size: Int64?

    var id: String { url.path }
    var displayPath: String { (url.path as NSString).abbreviatingWithTildeInPath }
}

enum AppLeftovers {
    static func canUninstall(url: URL, bundleID: String?) -> Bool {
        let path = url.standardizedFileURL.path
        guard path.hasSuffix(".app") else { return false }
        if path.hasPrefix("/System/") || path.hasPrefix("/usr/") { return false }
        guard let bundleID else { return true }
        if bundleID.hasPrefix("com.apple.") { return false }
        if bundleID == "com.opencast.app" || bundleID.hasPrefix("com.opencast.app.") { return false }
        return true
    }

    static func supportPaths(
        appName: String, bundleID: String?, home: URL, siblingBundleExists: Bool = false
    ) -> [URL] {
        let bundleID = validBundleID(bundleID)
        let identifiers = siblingBundleExists ? [] : bundleID.map { [$0] } ?? []
        let names = siblingBundleExists ? [] : nameVariants(appName)
        var found: [URL] = []
        var seen = Set<String>()

        func add(_ url: URL?) {
            guard let url, isSafeResult(url, home: home),
                FileManager.default.fileExists(atPath: url.path), seen.insert(url.path).inserted
            else { return }
            found.append(url)
        }

        for name in names {
            add(child(home, "Library/Application Support", name))
            add(child(home, "Library/Caches", name))
            add(child(home, "Library/Logs", name))
            add(child(home, "Library/Preferences", name + ".plist"))
            add(child(home, "Library/Saved Application State", name + ".savedState"))
        }
        for id in identifiers {
            add(child(home, "Library/Application Support", id))
            add(child(home, "Library/Application Scripts", id))
            add(child(home, "Library/Application Support/CrashReporter", id))
            add(child(home, "Library/Autosave Information", id))
            add(child(home, "Library/Caches", id))
            add(child(home, "Library/Caches/com.apple.nsurlsessiond/Downloads", id))
            add(child(home, "Library/Containers", id))
            add(child(home, "Library/Cookies", id + ".binarycookies"))
            add(child(home, "Library/HTTPStorages", id))
            add(child(home, "Library/HTTPStorages", id + ".binarycookies"))
            add(child(home, "Library/LaunchAgents", id + ".plist"))
            add(child(home, "Library/Logs", id))
            add(child(home, "Library/Preferences", id + ".plist"))
            add(child(home, "Library/Saved Application State", id + ".savedState"))
            add(child(home, "Library/SyncedPreferences", id + ".plist"))
            add(child(home, "Library/WebKit", id))
            add(child(home, "Library/WebKit/com.apple.WebKit.WebContent", id))

            for root in ["Library/Application Scripts", "Library/Containers", "Library/WebKit"] {
                for url in children(of: child(home, root), where: { $0.hasPrefix(id + ".") }) {
                    add(url)
                }
            }
            for url in children(
                of: child(home, "Library/Group Containers"),
                where: { $0 == id || $0.hasSuffix("." + id) || $0.hasPrefix(id + ".") }
            ) {
                add(url)
            }
            for url in children(
                of: child(home, "Library/Preferences/ByHost"),
                where: { $0.hasPrefix(id + ".") && $0.hasSuffix(".plist") }
            ) {
                add(url)
            }
            for url in children(
                of: child(home, "Library/LaunchAgents"),
                where: { $0.hasPrefix(id + ".") && $0.hasSuffix(".plist") }
            ) {
                add(url)
            }
        }

        return found.sorted { $0.path.localizedStandardCompare($1.path) == .orderedAscending }
    }

    private static let allowedRoots = [
        "Library/Application Scripts", "Library/Application Support", "Library/Autosave Information",
        "Library/Caches", "Library/Containers", "Library/Cookies", "Library/Group Containers",
        "Library/HTTPStorages", "Library/LaunchAgents", "Library/Logs", "Library/Preferences",
        "Library/Saved Application State", "Library/SyncedPreferences", "Library/WebKit",
    ]

    private static func isSafeResult(_ url: URL, home: URL) -> Bool {
        let path = url.standardizedFileURL.path
        let homePath = home.standardizedFileURL.path
        guard path != homePath, !path.contains("/../"), !path.hasSuffix("/..") else { return false }
        for root in allowedRoots {
            let rootPath = homePath + "/" + root
            if path == rootPath { return false }
            if path.hasPrefix(rootPath + "/") { return path.count > rootPath.count + 1 }
        }
        return false
    }

    private static func validBundleID(_ bundleID: String?) -> String? {
        guard let bundleID, bundleID.count >= 3, bundleID.contains("."),
            !bundleID.hasPrefix("."), !bundleID.hasSuffix("."), !bundleID.contains("..")
        else { return nil }
        let allowed = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz")
            .union(CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789.-_"))
        guard bundleID.unicodeScalars.allSatisfy({ allowed.contains($0) }) else { return nil }
        return bundleID
    }

    private static func nameVariants(_ appName: String) -> [String] {
        let name = appName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard name.count >= 3, !name.contains("/"), !name.contains(":") else { return [] }
        var variants = [name]
        if name.contains(" ") {
            for separator in ["", "-", "_"] {
                let variant = name.replacingOccurrences(of: " ", with: separator)
                if variant.count >= 3 { variants.append(variant) }
            }
        }
        var seen = Set<String>()
        return variants.filter { seen.insert($0).inserted }
    }

    private static func child(_ home: URL, _ root: String, _ name: String) -> URL? {
        guard !name.isEmpty, !name.hasPrefix("."), !name.contains("/") else { return nil }
        return home.appendingPathComponent(root).appendingPathComponent(name)
    }

    private static func child(_ home: URL, _ root: String) -> URL {
        home.appendingPathComponent(root)
    }

    private static func children(of root: URL, where predicate: (String) -> Bool) -> [URL] {
        guard
            let items = try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: nil, options: [])
        else { return [] }
        return items.filter { predicate($0.lastPathComponent) }
    }

    static func size(of url: URL) -> Int64? {
        let keys: Set<URLResourceKey> = [
            .totalFileSizeKey, .fileSizeKey, .isDirectoryKey, .isSymbolicLinkKey,
        ]
        guard let values = try? url.resourceValues(forKeys: keys), values.isSymbolicLink != true else {
            return nil
        }
        guard values.isDirectory == true else { return logicalSize(values) }
        guard
            let walker = FileManager.default.enumerator(
                at: url, includingPropertiesForKeys: Array(keys), options: [])
        else { return nil }
        var total: Int64 = 0
        for case let child as URL in walker {
            if Task.isCancelled { return nil }
            if let values = try? child.resourceValues(forKeys: keys), values.isSymbolicLink != true {
                total += logicalSize(values) ?? 0
            }
        }
        return total
    }

    private static func logicalSize(_ values: URLResourceValues) -> Int64? {
        if let size = values.totalFileSize { return Int64(size) }
        if let size = values.fileSize { return Int64(size) }
        return nil
    }

    static func remove(_ urls: [URL], permanently: Bool) -> Set<String> {
        var failed = Set<String>()
        for url in urls {
            do {
                if permanently {
                    try FileManager.default.removeItem(at: url)
                } else {
                    try FileManager.default.trashItem(at: url, resultingItemURL: nil)
                }
            } catch {
                failed.insert(url.path)
            }
        }
        return failed
    }
}
