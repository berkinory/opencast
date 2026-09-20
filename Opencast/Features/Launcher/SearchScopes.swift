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
        var result: [URL] = []

        for scope in scopes {
            let url = URL(fileURLWithPath: expand(scope))
            if url.pathExtension.lowercased() == "app" {
                guard isDirectory(url) else { continue }
                result.append(url)
                result.append(contentsOf: embeddedAppBundles(in: url))
                continue
            }

            let items = children(of: url)
            let apps = items.filter { $0.pathExtension.lowercased() == "app" && isDirectory($0) }
            result.append(contentsOf: apps)
            for app in apps {
                result.append(contentsOf: embeddedAppBundles(in: app))
            }

            let groupedDirectories = items.filter {
                $0.pathExtension.lowercased() != "app" && isDirectory($0)
            }
            for directory in groupedDirectories {
                let groupedApps = children(of: directory).filter {
                    $0.pathExtension.lowercased() == "app" && isDirectory($0)
                }
                result.append(contentsOf: groupedApps)
                for app in groupedApps {
                    result.append(contentsOf: embeddedAppBundles(in: app))
                }
            }
        }
        var seen = Set<String>()
        return result.filter { seen.insert($0.resolvingSymlinksInPath().standardizedFileURL.path).inserted }
    }

    private static func embeddedAppBundles(in app: URL) -> [URL] {
        ["Contents/Applications", "Contents/Developer/Applications"].flatMap { path in
            let directory = app.appendingPathComponent(path, isDirectory: true)
            return children(of: directory).filter { $0.pathExtension.lowercased() == "app" && isDirectory($0) }
        }
    }

    private static func children(of directory: URL) -> [URL] {
        let resolved = directory.resolvingSymlinksInPath()
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: resolved, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])) ?? []
        if resolved.path == directory.path { return children }
        return children.map { directory.appendingPathComponent($0.lastPathComponent) }
    }

    private static func isDirectory(_ url: URL) -> Bool {
        (try? url.resolvingSymlinksInPath().resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true
    }

    private static func trimTrailingSlash(_ path: String) -> String {
        var path = path.trimmingCharacters(in: .whitespaces)
        while path.count > 1 && path.hasSuffix("/") { path.removeLast() }
        return path
    }
}
