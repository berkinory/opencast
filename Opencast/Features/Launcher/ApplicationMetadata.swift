import Foundation

struct ApplicationMetadata: Equatable, Sendable {
    let name: String
    let bundleID: String?

    static func read(at url: URL, languages: [String] = Locale.preferredLanguages) -> Self? {
        let contents = url.appendingPathComponent("Contents")
        let info: [String: Any]
        let resources: URL
        if let dictionary = dictionary(at: contents.appendingPathComponent("Info.plist")) {
            info = dictionary
            resources = contents.appendingPathComponent("Resources")
        } else if let dictionary = dictionary(at: url.appendingPathComponent("Info.plist")) {
            info = dictionary
            resources = url
        } else {
            return nil
        }

        let table = dictionary(at: resources.appendingPathComponent("InfoPlist.loctable")) ?? [:]
        let tableLanguages = table.keys.filter { table[$0] is [String: Any] }
        let folderLanguages =
            ((try? FileManager.default.contentsOfDirectory(
                at: resources, includingPropertiesForKeys: nil)) ?? [])
            .filter { $0.pathExtension == "lproj" }
            .map { $0.deletingPathExtension().lastPathComponent }
        let localizations = Array(Set(folderLanguages + tableLanguages)).sorted()
        let preferred = Bundle.preferredLocalizations(from: localizations, forPreferences: languages)
        let fallbacks = [info["CFBundleDevelopmentRegion"] as? String, "Base"].compactMap { $0 }
        var localized: [String: Any] = [:]
        for language in preferred + fallbacks {
            guard !language.contains("/"), !language.contains("\\"), language != "..", language != "." else { continue }
            let path = resources.appendingPathComponent(language + ".lproj/InfoPlist.strings")
            if let values = dictionary(at: path) ?? table[language] as? [String: Any] {
                for (key, value) in values where localized[key] == nil { localized[key] = value }
            }
        }
        let candidates: [Any?] = ["CFBundleDisplayName", "CFBundleName"].map { key in
            let localizedValue = localized[key + "-macos"] ?? localized[key]
            let rawValue = info[key + "-macos"] ?? info[key]
            return localizedValue ?? rawValue
        }
        let name =
            candidates.compactMap { ($0 as? String)?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty } ?? url.deletingPathExtension().lastPathComponent
        return Self(name: name, bundleID: (info["CFBundleIdentifier-macos"] ?? info["CFBundleIdentifier"]) as? String)
    }

    private static func dictionary(at url: URL) -> [String: Any]? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return (try? PropertyListSerialization.propertyList(from: data, options: [], format: nil)) as? [String: Any]
    }
}
