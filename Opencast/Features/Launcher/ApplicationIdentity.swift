import Foundation

enum ApplicationIdentity {
    static let defaultsKey = "applicationPrimaryPaths"

    static func path(_ url: URL) -> String {
        url.resolvingSymlinksInPath().standardizedFileURL.path
    }

    static func key(for url: URL, bundleID: String?, primaryPaths: inout [String: String]) -> String {
        let path = path(url)
        guard let bundleID else { return path }
        if primaryPaths[bundleID] == nil { primaryPaths[bundleID] = path }
        return primaryPaths[bundleID] == path ? bundleID : path
    }
}
