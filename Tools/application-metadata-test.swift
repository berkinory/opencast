import Foundation

@main
struct ApplicationMetadataTests {
    static func main() throws {
        let fm = FileManager.default
        let root = fm.temporaryDirectory.appendingPathComponent("opencast-metadata-" + UUID().uuidString)
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app")
        let contents = app.appendingPathComponent("Contents")
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        let plist = contents.appendingPathComponent("Info.plist")
        func write(_ values: [String: String], to url: URL) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: values, format: .xml, options: 0)
            try data.write(to: url, options: .atomic)
        }
        func read() -> ApplicationMetadata? { ApplicationMetadata.read(at: app, languages: ["en"]) }
        precondition(read() == nil, "incomplete installations are not indexed")
        try write(["CFBundleName": "DynamicUniversalApp", "CFBundleIdentifier": "com.example.app"], to: plist)
        let cachedBundle = Bundle(url: app)!
        _ = cachedBundle.infoDictionary
        let initial = read()!
        precondition(initial.name == "DynamicUniversalApp")
        let stamp = try app.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        try write(["CFBundleDisplayName": "Example", "CFBundleIdentifier": "com.example.updated"], to: plist)
        let updatedStamp = try app.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
        precondition(stamp == updatedStamp)
        let updated = read()!
        precondition(updated.name == "Example" && updated.bundleID == "com.example.updated")
        precondition(initial != updated, "metadata changes must invalidate the scan cache")

        let localized = contents.appendingPathComponent("Resources/en.lproj")
        try fm.createDirectory(at: localized, withIntermediateDirectories: true)
        let strings = localized.appendingPathComponent("InfoPlist.strings")
        try write(["CFBundleDisplayName": "Localized Example"], to: strings)
        precondition(read()?.name == "Localized Example")
        try write(["CFBundleDisplayName": "Updated Localization"], to: strings)
        precondition(read()?.name == "Updated Localization", "localized names refresh in the same process")
        try Data("\"CFBundleDisplayName\" = \"Strings Format\";".utf8).write(to: strings)
        precondition(read()?.name == "Strings Format", "OpenStep strings files remain supported")
        try fm.removeItem(at: strings)
        precondition(read()?.name == "Example")
        let table = localized.deletingLastPathComponent().appendingPathComponent("InfoPlist.loctable")
        let translations = [
            "en": ["CFBundleDisplayName": "Table Name"],
            "tr": ["CFBundleDisplayName": "Türkçe Ad"],
        ]
        try PropertyListSerialization.data(fromPropertyList: translations, format: .binary, options: 0).write(to: table)
        precondition(read()?.name == "Table Name", "modern localization tables remain supported")
        precondition(ApplicationMetadata.read(at: app, languages: ["tr"])?.name == "Türkçe Ad")
        try PropertyListSerialization.data(
            fromPropertyList: ["en": ["CFBundleDisplayName": "Updated Table"]], format: .binary, options: 0
        ).write(to: table)
        precondition(read()?.name == "Updated Table")
        try PropertyListSerialization.data(
            fromPropertyList: ["en": ["CFBundleDisplayName": "Generic", "CFBundleDisplayName-macos": "Mac Name"]],
            format: .binary, options: 0
        ).write(to: table)
        precondition(read()?.name == "Mac Name", "localized platform-specific names take precedence")
        try fm.removeItem(at: table)
        try write(["CFBundleDisplayName": "Generic", "CFBundleDisplayName-macos": "Mac Name"], to: plist)
        precondition(read()?.name == "Mac Name", "raw platform-specific names take precedence")
        try Data("partial plist".utf8).write(to: plist)
        precondition(read() == nil, "a partially written plist must not poison the cache")
        try write(["CFBundleName": "Recovered"], to: plist)
        precondition(read()?.name == "Recovered")
        try write(["CFBundleName": " "], to: plist)
        precondition(read()?.name == "Example", "missing names fall back to the app filename")
        try fm.removeItem(at: app)
        precondition(read() == nil)
        try fm.createDirectory(at: contents, withIntermediateDirectories: true)
        try write(["CFBundleName": "Reinstalled"], to: plist)
        precondition(read()?.name == "Reinstalled", "reinstalling at the same path refreshes metadata")
        withExtendedLifetime(cachedBundle) {}
        print("application metadata tests passed")
    }
}
