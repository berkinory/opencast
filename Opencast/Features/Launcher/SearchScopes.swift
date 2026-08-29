import Foundation

enum SearchScopes {
    static let defaults: [String] = [
        "/Applications",
        "/Applications/Utilities",
        "/System/Applications",
        "/System/Applications/Utilities",
        "/System/Library/CoreServices/Applications",
        "/System/Volumes/Preboot/Cryptexes/App/System/Applications",
        "/System/Library/CoreServices/Finder.app",
        "~/Applications",
    ]

    static func abbreviate(_ path: String) -> String {
        let trimmed = trimTrailingSlash(path)
        return (trimmed as NSString).abbreviatingWithTildeInPath
    }

    static func expand(_ path: String) -> String {
        (trimTrailingSlash(path) as NSString).expandingTildeInPath
    }

    static func normalize(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.map(abbreviate).filter { !$0.isEmpty && seen.insert($0).inserted }
    }

    static func appBundles(in scopes: [String]) -> [URL] {
        let fileManager = FileManager.default
        var result: [URL] = []

        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension.lowercased() == "app" {
                guard fileManager.fileExists(atPath: url.path) else { continue }
                result.append(url)
                result.append(contentsOf: embeddedAppBundles(in: url))
                continue
            }

            guard
                let items = try? fileManager.contentsOfDirectory(
                    at: url,
                    includingPropertiesForKeys: nil,
                    options: [.skipsHiddenFiles]
                )
            else { continue }
            let apps = items.filter { $0.pathExtension.lowercased() == "app" }
            result.append(contentsOf: apps)
            for app in apps {
                result.append(contentsOf: embeddedAppBundles(in: app))
            }

            let groupedDirectories = items.filter {
                $0.hasDirectoryPath && $0.pathExtension.lowercased() != "app"
            }
            for directory in groupedDirectories {
                guard
                    let groupedItems = try? fileManager.contentsOfDirectory(
                        at: directory,
                        includingPropertiesForKeys: nil,
                        options: [.skipsHiddenFiles]
                    )
                else { continue }
                let groupedApps = groupedItems.filter { $0.pathExtension.lowercased() == "app" }
                result.append(contentsOf: groupedApps)
                for app in groupedApps {
                    result.append(contentsOf: embeddedAppBundles(in: app))
                }
            }
        }
        return result
    }

    private static func embeddedAppBundles(in app: URL) -> [URL] {
        let directory = app.appendingPathComponent("Contents/Applications", isDirectory: true)
        return
            (try? FileManager.default.contentsOfDirectory(
                at: directory,
                includingPropertiesForKeys: nil,
                options: [.skipsHiddenFiles]
            ))?.filter { $0.pathExtension.lowercased() == "app" } ?? []
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
