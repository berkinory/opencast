import Foundation

@MainActor
final class ExtensionSnapshotStore {
    private let directory: URL
    private let encoder: JSONEncoder
    private let decoder: JSONDecoder

    init(directory: URL? = nil) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        let base = directory ?? AppPaths.applicationSupport()
        let scoped =
            directory == nil
            ? base
            : base.appendingPathComponent(bundleID, isDirectory: true)
        self.directory = scoped.appendingPathComponent("ExtensionSnapshots", isDirectory: true)
        encoder = JSONEncoder()
        decoder = JSONDecoder()
        encoder.dateEncodingStrategy = .iso8601
        decoder.dateDecodingStrategy = .iso8601
    }

    func load(commandID: String) -> ExtensionMenuBarSnapshot? {
        guard let data = try? Data(contentsOf: url(for: commandID)) else { return nil }
        return try? decoder.decode(ExtensionMenuBarSnapshot.self, from: data)
    }

    func save(_ snapshot: ExtensionMenuBarSnapshot) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try encoder.encode(snapshot).write(to: url(for: snapshot.commandID), options: [.atomic])
        } catch {
            return
        }
    }

    func loadMetrics(commandID: String) -> ExtensionRuntimeMetrics? {
        guard let data = try? Data(contentsOf: metricsURL(for: commandID)) else { return nil }
        return try? decoder.decode(ExtensionRuntimeMetrics.self, from: data)
    }

    func saveMetrics(_ metrics: ExtensionRuntimeMetrics) {
        do {
            try FileManager.default.createDirectory(
                at: directory, withIntermediateDirectories: true)
            try encoder.encode(metrics).write(to: metricsURL(for: metrics.commandID), options: [.atomic])
        } catch {
            return
        }
    }

    private func url(for commandID: String) -> URL {
        directory.appendingPathComponent(safeName(commandID) + ".json")
    }

    private func metricsURL(for commandID: String) -> URL {
        directory.appendingPathComponent(safeName(commandID) + ".metrics.json")
    }

    private func safeName(_ value: String) -> String {
        value.map { character in
            character.isLetter || character.isNumber || character == "-" || character == "_"
                ? character : "_"
        }.map(String.init).joined().prefix(160).description
    }
}
