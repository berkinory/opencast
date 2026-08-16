import Foundation

enum FilePathResolver {
    static func resolve(_ input: String, fileManager: FileManager = .default) -> URL? {
        let value = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty else { return nil }

        let url: URL
        if let parsed = URL(string: value), parsed.isFileURL {
            url = parsed.standardizedFileURL
        } else {
            let path = NSString(string: value).expandingTildeInPath
            guard path.hasPrefix("/") else { return nil }
            url = URL(fileURLWithPath: path).standardizedFileURL
        }
        guard fileManager.fileExists(atPath: url.path) else { return nil }
        return url
    }
}
