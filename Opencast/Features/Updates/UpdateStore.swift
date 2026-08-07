import Combine
import Foundation
import Sparkle

@MainActor
final class UpdateStore: ObservableObject {
    enum HomebrewCheck: Equatable, Sendable {
        case upToDate
        case updateAvailable(current: String, latest: String)
        case unavailable(String)
    }

    private struct HomebrewResponse: Decodable, Sendable {
        let casks: [HomebrewCask]
    }

    private struct HomebrewCask: Decodable, Sendable {
        let installedVersions: [String]
        let currentVersion: String

        enum CodingKeys: String, CodingKey {
            case installedVersions = "installed_versions"
            case currentVersion = "current_version"
        }
    }

    private let defaults = UserDefaults.standard
    private let consentKey: String
    private let updaterController: SPUStandardUpdaterController?
    private var updaterStarted = false

    @Published private(set) var networkConsentGranted: Bool

    var isHomebrewManaged: Bool {
        DistributionMarker.current == .homebrew
    }

    var supportsSparkle: Bool {
        updaterController != nil
    }

    var automaticallyChecksForUpdates: Bool {
        networkConsentGranted && (updaterController?.updater.automaticallyChecksForUpdates ?? false)
    }

    var automaticallyDownloadsUpdates: Bool {
        automaticallyChecksForUpdates
            && (updaterController?.updater.automaticallyDownloadsUpdates ?? false)
    }

    init() {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        consentKey = "updates.networkConsent.\(bundleID)"
        networkConsentGranted = defaults.bool(forKey: consentKey)
        if DistributionMarker.current == .direct && bundleID != "com.opencast.app.dev" {
            updaterController = SPUStandardUpdaterController(
                startingUpdater: false,
                updaterDelegate: nil,
                userDriverDelegate: nil
            )
        } else {
            updaterController = nil
        }
    }

    func start() {
        guard networkConsentGranted else { return }
        startSparkleIfNeeded()
    }

    func setNetworkConsent(_ granted: Bool) {
        networkConsentGranted = granted
        defaults.set(granted, forKey: consentKey)
        guard !granted, let updaterController else { return }
        objectWillChange.send()
        updaterController.updater.automaticallyDownloadsUpdates = false
        updaterController.updater.automaticallyChecksForUpdates = false
    }

    func grantNetworkConsent() {
        setNetworkConsent(true)
        startSparkleIfNeeded()
    }

    func setAutomaticallyChecksForUpdates(_ enabled: Bool) {
        guard let updaterController else { return }
        if enabled {
            guard networkConsentGranted else { return }
            startSparkleIfNeeded()
        }
        objectWillChange.send()
        updaterController.updater.automaticallyChecksForUpdates = enabled
        if !enabled {
            updaterController.updater.automaticallyDownloadsUpdates = false
        }
    }

    func setAutomaticallyDownloadsUpdates(_ enabled: Bool) {
        guard networkConsentGranted, automaticallyChecksForUpdates, let updaterController else { return }
        objectWillChange.send()
        updaterController.updater.automaticallyDownloadsUpdates = enabled
    }

    func checkNow() {
        guard networkConsentGranted, let updaterController else { return }
        startSparkleIfNeeded()
        updaterController.checkForUpdates(nil)
    }

    func checkHomebrew() async -> HomebrewCheck {
        guard isHomebrewManaged else {
            return .unavailable("This installation is not managed by Homebrew.")
        }
        do {
            let response = try await Task.detached(priority: .utility) {
                try Self.runHomebrewOutdated()
            }.value
            guard let cask = response.casks.first else { return .upToDate }
            let current = cask.installedVersions.first ?? "unknown"
            return .updateAvailable(current: current, latest: cask.currentVersion)
        } catch {
            return .unavailable(error.localizedDescription)
        }
    }

    private func startSparkleIfNeeded() {
        guard !updaterStarted, let updaterController else { return }
        updaterStarted = true
        updaterController.startUpdater()
    }

    private nonisolated static func runHomebrewOutdated() throws -> HomebrewResponse {
        let candidates =
            ["/opt/homebrew/bin/brew", "/usr/local/bin/brew"]
            + (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map { String($0) + "/brew" }
        guard let executable = candidates.first(where: { FileManager.default.isExecutableFile(atPath: $0) })
        else {
            throw NSError(
                domain: "UpdateStore", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Homebrew was not found."])
        }

        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = ["outdated", "--cask", "--json=v2", "opencast"]
        process.environment = ProcessInfo.processInfo.environment.merging(
            ["HOMEBREW_NO_AUTO_UPDATE": "1", "HOMEBREW_NO_ENV_HINTS": "1"],
            uniquingKeysWith: { _, new in new }
        )
        process.standardOutput = output
        process.standardError = errors
        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        guard process.terminationStatus == 0 else {
            let message =
                String(data: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
                ?? "Homebrew could not check for updates."
            throw NSError(
                domain: "UpdateStore", code: 2,
                userInfo: [NSLocalizedDescriptionKey: message])
        }
        return try JSONDecoder().decode(HomebrewResponse.self, from: data)
    }
}

enum DistributionMarker {
    case direct
    case homebrew

    static var current: DistributionMarker {
        let url = AppPaths.applicationSupport()
            .appendingPathComponent("distribution", isDirectory: false)
        return (try? String(contentsOf: url, encoding: .utf8))?
            .trimmingCharacters(in: .whitespacesAndNewlines) == "homebrew"
            ? .homebrew : .direct
    }
}
