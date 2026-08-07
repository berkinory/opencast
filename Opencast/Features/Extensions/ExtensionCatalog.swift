import Foundation
import Combine

@MainActor
final class ExtensionCatalog: ObservableObject {
    @Published private(set) var commands: [ExtensionCommand] = []

    let directory: URL
    private var disabledNames = Set<String>()
    private let decoder = JSONDecoder()

    init(directory: URL? = nil) {
        self.directory = directory ?? Self.defaultDirectory()
    }

    func refresh() {
        guard
            let entries = try? FileManager.default.contentsOfDirectory(
                at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else {
            commands = []
            return
        }

        commands =
            entries
            .filter { $0.pathExtension == "ocx" }
            .flatMap { loadCommands(from: $0) }
            .filter { !disabledNames.contains($0.extensionName) }
            .sorted {
                $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending
            }
    }

    func setDisabledNames(_ names: Set<String>) {
        disabledNames = names
        refresh()
    }

    func command(forEntryID id: String) -> ExtensionCommand? {
        commands.first { $0.id == id }
    }

    private func loadCommands(from bundleURL: URL) -> [ExtensionCommand] {
        let manifestURL = bundleURL.appendingPathComponent("manifest.json")
        guard let data = try? Data(contentsOf: manifestURL),
            let manifest = try? decoder.decode(ExtensionManifest.self, from: data),
            manifest.schemaVersion == 1
        else { return [] }
        return manifest.commands.map {
            ExtensionCommand(manifest: manifest, command: $0, bundleURL: bundleURL)
        }
    }

    private static func defaultDirectory() -> URL {
        let applicationSupport = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask
        ).first!
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        return applicationSupport.appendingPathComponent(bundleID, isDirectory: true)
            .appendingPathComponent("Extensions", isDirectory: true)
    }
}
