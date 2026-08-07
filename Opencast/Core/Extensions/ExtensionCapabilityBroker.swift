import AppKit
import ApplicationServices
import Combine
import Darwin
import Foundation
import SQLite3

struct ExtensionCapabilityResult: Sendable {
    let ok: Bool
    let value: AnySendable?
    let error: String?

    static func success(_ value: AnySendable? = nil) -> Self {
        Self(ok: true, value: value, error: nil)
    }

    static func denied(_ message: String) -> Self {
        Self(ok: false, value: nil, error: message)
    }
}

struct AnySendable: @unchecked Sendable {
    let value: Any
}

@MainActor
final class ExtensionCapabilityBroker: ObservableObject {
    private static let persistentStorageQuota = 4 * 1024 * 1024
    private static let cacheStorageQuota = 16 * 1024 * 1024
    private let storageDirectory: URL
    private let auditURL: URL
    private let processProvider: ExtensionProcessProvider
    private let portProvider: ExtensionPortProvider
    private let metricsProvider: ExtensionSystemMetricsProvider
    private let jobManager: ExtensionProcessJobManager
    private let networkSession: URLSession
    private let networkConsentKey: String
    private let previousApplication: () -> NSRunningApplication?
    private let confirmAction: (String, String, String) -> Bool
    private var networkConsentGranted: Bool

    init(
        storageDirectory: URL? = nil,
        previousApplication: @escaping () -> NSRunningApplication?,
        confirmAction: @escaping (String, String, String) -> Bool
    ) {
        let bundleID = Bundle.main.bundleIdentifier ?? "com.opencast.app"
        let base = storageDirectory ?? AppPaths.applicationSupport()
        let scoped =
            storageDirectory == nil
            ? base
            : base.appendingPathComponent(bundleID, isDirectory: true)
        self.storageDirectory =
            scoped
            .appendingPathComponent("ExtensionStorage", isDirectory: true)
        auditURL = self.storageDirectory
            .deletingLastPathComponent()
            .appendingPathComponent("ExtensionCapabilityAudit.jsonl")
        networkConsentKey = "extensionNetworkConsent." + bundleID
        networkConsentGranted = true
        let protectedPID = Int32(getpid())
        processProvider = ExtensionProcessProvider(protectedPIDs: [protectedPID])
        portProvider = ExtensionPortProvider()
        metricsProvider = ExtensionSystemMetricsProvider()
        jobManager = ExtensionProcessJobManager()
        self.previousApplication = previousApplication
        self.confirmAction = confirmAction

        let configuration = URLSessionConfiguration.ephemeral
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        networkSession = URLSession(configuration: configuration)
    }

    func setNetworkConsent(_ granted: Bool) {
        networkConsentGranted = granted
        UserDefaults.standard.set(granted, forKey: networkConsentKey)
    }

    func handle(
        capability: String,
        payload: [String: Any],
        command: ExtensionCommand,
        requestID: String? = nil,
        onProgress: ExtensionProcessJobManager.ProgressHandler? = nil
    ) async -> ExtensionCapabilityResult {
        guard command.capabilities.contains(capability) else {
            audit(capability: capability, command: command, outcome: "undeclared")
            return .denied("Capability " + capability + " is not declared by this extension.")
        }

        switch capability {
        case "clipboard.read":
            return .success(AnySendable(value: NSPasteboard.general.string(forType: .string) ?? ""))
        case "clipboard.write":
            guard let text = payload["text"] as? String else {
                return .denied("clipboard.write requires a text value.")
            }
            Paster.copyString(text)
            return .success(AnySendable(value: true))
        case "clipboard.paste":
            guard let text = payload["text"] as? String else {
                return .denied("clipboard.paste requires a text value.")
            }
            Paster.pasteString(text, previousApp: previousApplication())
            return .success(AnySendable(value: true))
        case "selectedText.read":
            return selectedText()
        case "finder.selection.read":
            return await finderSelection()
        case "open.url":
            guard let rawURL = payload["url"] as? String, let url = URL(string: rawURL),
                ["http", "https"].contains(url.scheme?.lowercased())
            else { return .denied("Only http and https URLs can be opened.") }
            return .success(AnySendable(value: NSWorkspace.shared.open(url)))
        case "open.application":
            guard let path = payload["path"] as? String else {
                return .denied("open.application requires a path.")
            }
            return .success(AnySendable(value: NSWorkspace.shared.open(URL(fileURLWithPath: path))))
        case "finder.reveal":
            guard let path = payload["path"] as? String else {
                return .denied("finder.reveal requires a path.")
            }
            NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
            return .success(AnySendable(value: true))
        case "filesystem.read":
            return readFile(payload: payload, command: command)
        case "filesystem.write":
            return writeFile(payload: payload, command: command)
        case "filesystem.list":
            return listFiles(payload: payload, command: command)
        case "filesystem.pick":
            return pickFile(payload: payload, command: command)
        case "filesystem.quickLook":
            return quickLook(payload: payload, command: command)
        case "preferences.read":
            return .success(AnySendable(value: preferenceValues(for: command)))
        case "storage.read":
            return readStorage(payload: payload, command: command)
        case "storage.write":
            return writeStorage(payload: payload, command: command)
        case "storage.delete":
            return deleteStorage(payload: payload, command: command)
        case "storage.sqlite":
            return sqlite(payload: payload, command: command)
        case "application.list":
            return applicationList()
        case "application.frontmost":
            return frontmostApplication()
        case "applescript.execute":
            return await executeAppleScript(payload: payload, command: command)
        case "browser.read":
            return await browserRead(payload: payload, command: command)
        case "browser.mutate":
            return await browserMutate(payload: payload, command: command)
        case "process.execute":
            return await executeProcess(
                payload: payload, command: command, requestID: requestID, onProgress: onProgress)
        case "process.cancel":
            guard let jobID = payload["jobID"] as? String, !jobID.isEmpty else {
                return .denied("process.cancel requires a job ID.")
            }
            guard jobManager.cancel(jobID: jobID, owner: command.extensionName) else {
                return .denied("The process job was not found for this extension.")
            }
            return .success(AnySendable(value: true))
        case "process.inspect":
            return await inspectProcesses(payload: payload, command: command)
        case "process.terminate":
            return await terminateProcess(payload: payload, command: command)
        case "process.restart":
            return await restartProcess(payload: payload, command: command)
        case "ports.inspect":
            return await inspectPorts(payload: payload, command: command)
        case "system.metrics.read":
            let snapshot = await metricsProvider.snapshot()
            return encoded(snapshot)
        case "network.request":
            return await requestNetwork(
                payload: payload, command: command, requestID: requestID, onProgress: onProgress)
        case "menuBar.publishSnapshot":
            return .denied("Menu-bar publishing is handled by the scheduler, not a direct capability call.")
        default:
            return .denied("Unsupported capability: " + capability)
        }
    }

    func preferenceValues(for command: ExtensionCommand) -> [String: Any] {
        Dictionary(
            uniqueKeysWithValues: command.preferences.compactMap { preference in
                guard let rawValue = preference.defaultValue else { return nil }
                if preference.type == "checkbox" {
                    return (preference.name, rawValue == "true")
                }
                return (preference.name, rawValue)
            })
    }

    private func selectedText() -> ExtensionCapabilityResult {
        guard Permissions.ensureAccessibility() else {
            return .denied("Accessibility permission is required to read selected text.")
        }
        guard let application = previousApplication() else {
            return .success(AnySendable(value: ""))
        }
        let element = AXUIElementCreateApplication(application.processIdentifier)
        var value: CFTypeRef?
        let result = AXUIElementCopyAttributeValue(element, kAXFocusedUIElementAttribute as CFString, &value)
        guard result == .success, let focused = value else {
            return .success(AnySendable(value: ""))
        }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else {
            return .success(AnySendable(value: ""))
        }
        var selected: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(focused as! AXUIElement, kAXSelectedTextAttribute as CFString, &selected)
                == .success,
            let text = selected as? String
        else { return .success(AnySendable(value: "")) }
        return .success(AnySendable(value: text))
    }

    private func finderSelection() async -> ExtensionCapabilityResult {
        let script = "tell application \"Finder\" to get POSIX path of (selection as alias list)"
        do {
            let result = try await ExtensionFixedCommand.run(
                path: "/usr/bin/osascript", arguments: ["-e", script], timeout: 5, outputLimit: 256 * 1024)
            guard result.status == 0 else { return .denied(result.stderr) }
            let paths = result.stdout.split(whereSeparator: \.isNewline).map(String.init)
            return .success(AnySendable(value: paths))
        } catch { return .denied(error.localizedDescription) }
    }

    private func allowedFileURL(_ rawPath: String, payload: [String: Any], command: ExtensionCommand) -> URL? {
        guard rawPath.count <= 4096, !rawPath.contains("\0") else { return nil }
        let home = FileManager.default.homeDirectoryForCurrentUser.standardizedFileURL
        let extensionRoot = command.bundleURL.standardizedFileURL
        let path = rawPath.hasPrefix("/") ? rawPath : extensionRoot.appendingPathComponent(rawPath).path
        let url = URL(fileURLWithPath: path).standardizedFileURL
        let roots = command.filesystemRoots
        let homeRoots = roots.compactMap { root -> URL? in
            if root == "home" { return home }
            guard root.hasPrefix("home/") else { return nil }
            return home.appendingPathComponent(String(root.dropFirst("home/".count)))
                .standardizedFileURL
        }
        let allowed =
            homeRoots.contains { url.path == $0.path || url.path.hasPrefix($0.path + "/") }
            || (roots.contains("extension")
                && (url.path == extensionRoot.path || url.path.hasPrefix(extensionRoot.path + "/")))
        guard allowed,
            !url.path.hasPrefix("/System/"), !url.path.hasPrefix("/private/var/db/")
        else { return nil }
        return url
    }

    private func readFile(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let path = payload["path"] as? String, let url = allowedFileURL(path, payload: payload, command: command),
            let data = try? Data(contentsOf: url), data.count <= 4 * 1024 * 1024
        else { return .denied("filesystem.read is restricted to declared extension or home paths.") }
        return .success(
            AnySendable(value: [
                "path": url.path,
                "dataBase64": data.base64EncodedString(),
                "text": String(decoding: data, as: UTF8.self),
            ]))
    }

    private func writeFile(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let path = payload["path"] as? String, let url = allowedFileURL(path, payload: payload, command: command)
        else {
            return .denied("filesystem.write is restricted to declared extension or home paths.")
        }
        let data: Data?
        if let encoded = payload["dataBase64"] as? String {
            data = Data(base64Encoded: encoded)
        } else if let text = payload["text"] as? String {
            data = text.data(using: .utf8)
        } else {
            data = nil
        }
        guard let data, data.count <= 4 * 1024 * 1024 else { return .denied("filesystem.write is limited to 4 MB.") }
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            return .success(AnySendable(value: true))
        } catch { return .denied(error.localizedDescription) }
    }

    private func listFiles(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let path = payload["path"] as? String, let url = allowedFileURL(path, payload: payload, command: command),
            let entries = try? FileManager.default.contentsOfDirectory(
                at: url, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
        else { return .denied("filesystem.list is restricted to declared extension or home paths.") }
        return .success(
            AnySendable(value: entries.prefix(512).map { ["name": $0.lastPathComponent, "path": $0.path] }))
    }

    private func pickFile(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        let panel = NSOpenPanel()
        panel.canChooseFiles = payload["directory"] as? Bool != true
        panel.canChooseDirectories = payload["directory"] as? Bool == true
        panel.allowsMultipleSelection = payload["multiple"] as? Bool == true
        guard panel.runModal() == .OK else { return .success(AnySendable(value: [])) }
        let paths = panel.urls.compactMap { allowedFileURL($0.path, payload: payload, command: command)?.path }
        return .success(AnySendable(value: paths))
    }

    private func quickLook(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let path = payload["path"] as? String, let url = allowedFileURL(path, payload: payload, command: command)
        else {
            return .denied("filesystem.quickLook is restricted to declared paths.")
        }
        return .success(AnySendable(value: NSWorkspace.shared.open(url)))
    }

    private func applicationList() -> ExtensionCapabilityResult {
        let apps = NSWorkspace.shared.runningApplications.compactMap { app -> [String: Any]? in
            guard let url = app.bundleURL else { return nil }
            return [
                "name": app.localizedName ?? url.deletingPathExtension().lastPathComponent,
                "bundleID": app.bundleIdentifier as Any, "path": url.path,
            ]
        }
        return .success(AnySendable(value: apps))
    }

    private func frontmostApplication() -> ExtensionCapabilityResult {
        guard let app = NSWorkspace.shared.frontmostApplication else { return .success(AnySendable(value: NSNull())) }
        return .success(
            AnySendable(value: [
                "name": app.localizedName as Any,
                "bundleID": app.bundleIdentifier as Any,
                "pid": app.processIdentifier,
                "path": app.bundleURL?.path as Any,
            ]))
    }

    private func executeAppleScript(payload: [String: Any], command: ExtensionCommand) async
        -> ExtensionCapabilityResult
    {
        guard let script = payload["script"] as? String, script.count <= 64 * 1024 else {
            return .denied("applescript.execute requires a script smaller than 64 KB.")
        }
        let language = payload["language"] as? String == "JavaScript" ? "JavaScript" : "AppleScript"
        do {
            let args = language == "JavaScript" ? ["-l", "JavaScript", "-e", script] : ["-e", script]
            let result = try await ExtensionFixedCommand.run(
                path: "/usr/bin/osascript", arguments: args, timeout: 15, outputLimit: 512 * 1024)
            guard result.status == 0 else { return .denied(result.stderr) }
            return .success(AnySendable(value: result.stdout))
        } catch { return .denied(error.localizedDescription) }
    }

    private func browserRead(payload: [String: Any], command: ExtensionCommand) async -> ExtensionCapabilityResult {
        let browser = (payload["browser"] as? String ?? "Safari").lowercased()
        let app = browser == "chrome" ? "Google Chrome" : browser == "arc" ? "Arc" : "Safari"
        let resource = payload["resource"] as? String ?? "tabs"
        guard ["tabs", "history", "bookmarks"].contains(resource) else {
            return .denied("Unsupported browser read resource.")
        }
        let expression: String
        switch resource {
        case "history": expression = "tell application \"\(app)\" to get {name, URL} of every item of history"
        case "bookmarks": expression = "tell application \"\(app)\" to get name of every bookmark item of bookmarks"
        default: expression = "tell application \"\(app)\" to get URL of every tab of every window"
        }
        do {
            let result = try await ExtensionFixedCommand.run(
                path: "/usr/bin/osascript", arguments: ["-e", expression], timeout: 10, outputLimit: 512 * 1024)
            guard result.status == 0 else { return .denied(result.stderr) }
            return .success(
                AnySendable(
                    value: result.stdout.split(separator: ",").map {
                        String($0).trimmingCharacters(in: .whitespacesAndNewlines)
                    }))
        } catch { return .denied(error.localizedDescription) }
    }

    private func browserMutate(payload: [String: Any], command: ExtensionCommand) async -> ExtensionCapabilityResult {
        guard let browserValue = payload["browser"] as? String else {
            return .denied("browser.mutate requires a browser.")
        }
        let browser = browserValue.lowercased()
        let app = browser == "chrome" ? "Google Chrome" : browser == "arc" ? "Arc" : "Safari"
        guard let operation = payload["operation"] as? String else {
            return .denied("browser.mutate requires an operation.")
        }
        let script: String
        switch operation {
        case "closeTab":
            guard let index = payload["index"] as? Int, index > 0 else {
                return .denied("closeTab requires a positive tab index.")
            }
            script = "tell application \"\(app)\" to close tab \(index) of front window"
        case "createBookmark":
            guard let title = payload["title"] as? String, title.count <= 240,
                let url = payload["url"] as? String, let parsedURL = URL(string: url),
                ["http", "https"].contains(parsedURL.scheme?.lowercased())
            else { return .denied("createBookmark requires a valid http or https URL.") }
            let escapedTitle = title.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedURL = url.replacingOccurrences(of: "\"", with: "\\\"")
            script =
                "tell application \"\(app)\" to make new bookmark item at end of bookmarks with properties {name:\"\(escapedTitle)\", URL:\"\(escapedURL)\"}"
        default:
            return .denied("Unsupported browser mutation.")
        }
        do {
            let result = try await ExtensionFixedCommand.run(
                path: "/usr/bin/osascript", arguments: ["-e", script], timeout: 10)
            guard result.status == 0 else { return .denied(result.stderr) }
            return .success(AnySendable(value: true))
        } catch { return .denied(error.localizedDescription) }
    }

    private func storageRoot(payload: [String: Any], command: ExtensionCommand) -> URL {
        let namespace = (payload["namespace"] as? String) == "cache" ? "cache" : "persistent"
        return
            storageDirectory
            .appendingPathComponent(command.extensionName, isDirectory: true)
            .appendingPathComponent(namespace, isDirectory: true)
    }

    private func sqlite(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let query = payload["query"] as? String, query.count <= 16 * 1024 else {
            return .denied("storage.sqlite requires a bounded SQL query.")
        }
        let lowered = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !lowered.contains("attach "), !lowered.contains("pragma "), !lowered.contains("vacuum") else {
            return .denied("This SQLite operation is not allowed.")
        }
        let root = storageDirectory.appendingPathComponent(command.extensionName, isDirectory: true)
        let url = root.appendingPathComponent("extension.sqlite3")
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 4 * 1024 * 1024 {
            return .denied("The extension database exceeds the 4 MB quota.")
        }
        do { try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) } catch {
            return .denied(error.localizedDescription)
        }

        var database: OpaquePointer?
        guard sqlite3_open_v2(url.path, &database, SQLITE_OPEN_CREATE | SQLITE_OPEN_READWRITE, nil) == SQLITE_OK,
            let database
        else { sqlite3_close(database); return .denied("Could not open the extension database.") }
        defer { sqlite3_close(database) }
        var statement: OpaquePointer?
        guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK, let statement
        else { return .denied(String(cString: sqlite3_errmsg(database))) }
        defer { sqlite3_finalize(statement) }
        let params = payload["params"] as? [Any] ?? []
        guard params.count <= 64 else { return .denied("Too many SQLite parameters.") }
        for (index, value) in params.enumerated() {
            let position = Int32(index + 1)
            if let value = value as? String {
                sqlite3_bind_text(statement, position, value, -1, unsafeBitCast(-1, to: sqlite3_destructor_type.self))
            } else if let value = value as? Int {
                sqlite3_bind_int64(statement, position, sqlite3_int64(value))
            } else if let value = value as? Double {
                sqlite3_bind_double(statement, position, value)
            } else if value is NSNull {
                sqlite3_bind_null(statement, position)
            } else {
                return .denied("SQLite parameters must be strings, numbers, or null.")
            }
        }
        var rows: [[String: Any]] = []
        while sqlite3_step(statement) == SQLITE_ROW {
            var row: [String: Any] = [:]
            for index in 0..<sqlite3_column_count(statement) {
                let name = String(cString: sqlite3_column_name(statement, index))
                switch sqlite3_column_type(statement, index) {
                case SQLITE_INTEGER: row[name] = Int(sqlite3_column_int64(statement, index))
                case SQLITE_FLOAT: row[name] = sqlite3_column_double(statement, index)
                case SQLITE_TEXT: row[name] = String(cString: sqlite3_column_text(statement, index))
                case SQLITE_BLOB:
                    let length = sqlite3_column_bytes(statement, index)
                    if let bytes = sqlite3_column_blob(statement, index) {
                        row[name] = Data(bytes: bytes, count: Int(length)).base64EncodedString()
                    }
                default: row[name] = NSNull()
                }
            }
            rows.append(row)
            if rows.count >= 512 { break }
        }
        let resultCode = sqlite3_errcode(database)
        guard resultCode == SQLITE_OK || resultCode == SQLITE_ROW || resultCode == SQLITE_DONE else {
            return .denied(String(cString: sqlite3_errmsg(database)))
        }
        if let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize, size > 4 * 1024 * 1024 {
            return .denied("The extension database exceeds the 4 MB quota.")
        }
        return .success(AnySendable(value: ["rows": rows, "changes": Int(sqlite3_changes(database))]))
    }

    private func storageURL(payload: [String: Any], command: ExtensionCommand) -> URL {
        let key = (payload["key"] as? String ?? "value")
            .replacingOccurrences(of: "/", with: "_")
            .prefix(120)
        return storageRoot(payload: payload, command: command)
            .appendingPathComponent(String(key) + ".json")
    }

    private func readStorage(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        let url = storageURL(payload: payload, command: command)
        guard let data = try? Data(contentsOf: url),
            let value = try? JSONSerialization.jsonObject(with: data)
        else { return .success(AnySendable(value: NSNull())) }
        return .success(AnySendable(value: value))
    }

    private func writeStorage(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        guard let value = payload["value"], JSONSerialization.isValidJSONObject(value) else {
            return .denied("storage.write requires a JSON value.")
        }
        guard let data = try? JSONSerialization.data(withJSONObject: value, options: [.sortedKeys]),
            data.count <= 512 * 1024
        else { return .denied("storage values are limited to 512 KB.") }
        let url = storageURL(payload: payload, command: command)
        let previousData = try? Data(contentsOf: url)
        do {
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try data.write(to: url, options: [.atomic])
            try enforceStorageQuota(command: command, namespace: payload["namespace"] as? String)
            return .success(AnySendable(value: true))
        } catch {
            if let previousData {
                try? previousData.write(to: url, options: [.atomic])
            } else {
                try? FileManager.default.removeItem(at: url)
            }
            return .denied("Extension storage quota exceeded.")
        }
    }

    private func deleteStorage(payload: [String: Any], command: ExtensionCommand) -> ExtensionCapabilityResult {
        let url = storageURL(payload: payload, command: command)
        do {
            try FileManager.default.removeItem(at: url)
        } catch CocoaError.fileNoSuchFile {
        } catch {
            return .denied("Could not delete extension storage.")
        }
        return .success(AnySendable(value: true))
    }

    private func enforceStorageQuota(command: ExtensionCommand, namespace: String?) throws {
        let isCache = namespace == "cache"
        let root = storageRoot(payload: ["namespace": isCache ? "cache" : "persistent"], command: command)
        let quota = isCache ? Self.cacheStorageQuota : Self.persistentStorageQuota
        let files = try storageFiles(in: root)
        var total = files.reduce(0) { $0 + $1.size }
        guard total > quota else { return }
        if isCache {
            for file in files.sorted(by: { $0.date < $1.date }) {
                try? FileManager.default.removeItem(at: file.url)
                total -= file.size
                if total <= quota { return }
            }
        }
        throw NSError(domain: "OpencastExtensionStorage", code: 1)
    }

    private func storageFiles(in root: URL) throws -> [(url: URL, size: Int, date: Date)] {
        guard
            let enumerator = FileManager.default.enumerator(
                at: root, includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey]
            )
        else { return [] }
        return enumerator.compactMap { item in
            guard let url = item as? URL,
                let values = try? url.resourceValues(forKeys: [.fileSizeKey, .contentModificationDateKey]),
                let size = values.fileSize,
                let date = values.contentModificationDate
            else { return nil }
            return (url, size, date)
        }
    }

    private func executeProcess(
        payload: [String: Any],
        command: ExtensionCommand,
        requestID: String?,
        onProgress: ExtensionProcessJobManager.ProgressHandler?
    ) async -> ExtensionCapabilityResult {
        guard let rawCommand = payload["command"] as? String,
            rawCommand.count <= 512,
            let args = payload["args"] as? [String],
            args.count <= 64,
            args.allSatisfy({ $0.count <= 4096 && !$0.contains("\0") }),
            args.joined().count <= 64 * 1024
        else {
            return .denied("process.execute requires a command and bounded arguments.")
        }

        let options = payload["options"] as? [String: Any] ?? [:]
        let usesShell = options["shell"] as? Bool == true
        if usesShell && !command.shell {
            return .denied("Shell execution must be declared in opencast.json.")
        }
        let executable = usesShell ? "/bin/zsh" : URL(fileURLWithPath: rawCommand).standardizedFileURL.path
        guard usesShell || command.executables.contains(executable) else {
            audit(capability: "process.execute", command: command, outcome: "blocked-executable")
            return .denied("The executable must be declared in opencast.json.")
        }

        let processArguments =
            usesShell
            ? ["-lc", ([rawCommand] + args.map(shellQuote)).joined(separator: " ")]
            : args
        let streaming = options["stream"] as? Bool == true
        let timeoutLimit = streaming ? 120 : 30
        let timeout = min(max(options["timeout"] as? Double ?? 5, 0.1), Double(timeoutLimit))
        var input: Data?
        if let rawInput = options["input"] as? String {
            guard rawInput.utf8.count <= 64 * 1024 else {
                return .denied("process.execute input is too large.")
            }
            input = rawInput.data(using: .utf8)
        } else {
            input = nil
        }

        if streaming {
            guard let onProgress else {
                return .denied("Streaming process execution is unavailable in this host.")
            }
            do {
                let job = try jobManager.start(
                    path: executable,
                    arguments: processArguments,
                    input: input,
                    timeout: timeout,
                    owner: command.extensionName,
                    requestID: requestID ?? "process-execute",
                    progress: onProgress
                )
                audit(capability: "process.execute", command: command, outcome: "started-" + job.jobID)
                return encoded(job)
            } catch {
                audit(capability: "process.execute", command: command, outcome: "failed")
                return .denied(error.localizedDescription)
            }
        }

        do {
            let result = try await ExtensionFixedCommand.run(
                path: executable,
                arguments: processArguments,
                timeout: timeout,
                input: input,
                outputLimit: 256 * 1024
            )
            audit(capability: "process.execute", command: command, outcome: "status-" + String(result.status))
            return .success(
                AnySendable(value: [
                    "stdout": result.stdout,
                    "stderr": result.stderr,
                    "status": result.status,
                    "timedOut": result.timedOut,
                ]))
        } catch {
            audit(capability: "process.execute", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func inspectProcesses(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        do {
            let processes = try await processProvider.snapshot()
            let sortBy = payload["sortBy"] as? String
            let sorted = processes.sorted { left, right in
                switch sortBy {
                case "memory": return left.memoryPercent > right.memoryPercent
                case "name": return left.name.localizedCaseInsensitiveCompare(right.name) == .orderedAscending
                default: return left.cpuPercent > right.cpuPercent
                }
            }
            let limit = min(max(payload["limit"] as? Int ?? 256, 1), 512)
            audit(capability: "process.inspect", command: command, outcome: "success")
            return encoded(Array(sorted.prefix(limit)))
        } catch {
            audit(capability: "process.inspect", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func terminateProcess(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        guard let pid = payload["pid"] as? Int, pid > 1, pid <= Int(Int32.max) else {
            return .denied("process.terminate requires a valid PID.")
        }
        let signal = processSignal(payload["signal"])
        let includeDescendants = payload["includeDescendants"] as? Bool ?? false
        let title = signal == .kill ? "Force Kill Process" : "Terminate Process"
        let message = "PID " + String(pid) + (includeDescendants ? " and its descendants" : "") + " will be terminated."
        guard
            confirmAction(title, message, title)
        else {
            return .denied("Process termination was cancelled.")
        }

        do {
            let termination = try await processProvider.terminate(
                pid: Int32(pid), signal: signal, includeDescendants: includeDescendants)
            audit(capability: "process.terminate", command: command, outcome: "success")
            return encoded(termination)
        } catch {
            audit(capability: "process.terminate", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func restartProcess(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        guard let pid = payload["pid"] as? Int, pid > 1, pid <= Int(Int32.max) else {
            return .denied("process.restart requires a valid PID.")
        }
        let force = payload["force"] as? Bool ?? false
        let title = force ? "Force Restart Process" : "Restart Process"
        guard
            confirmAction(title, "PID \(pid) will be terminated and relaunched.", title)
        else {
            return .denied("Process restart was cancelled.")
        }
        do {
            return encoded(try await processProvider.restart(pid: Int32(pid), force: force))
        } catch {
            return .denied(error.localizedDescription)
        }
    }

    private func inspectPorts(
        payload: [String: Any], command: ExtensionCommand
    ) async -> ExtensionCapabilityResult {
        do {
            let ports = try await portProvider.snapshot()
            let limit = min(max(payload["limit"] as? Int ?? 256, 1), 512)
            audit(capability: "ports.inspect", command: command, outcome: "success")
            return encoded(Array(ports.prefix(limit)))
        } catch {
            audit(capability: "ports.inspect", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func processSignal(_ value: Any?) -> ExtensionProcessSignal {
        if let raw = value as? Int, let signal = ExtensionProcessSignal(rawValue: Int32(raw)) {
            return signal
        }
        if let raw = value as? String {
            switch raw.uppercased() {
            case "SIGKILL", "KILL", "9": return .kill
            default: return .term
            }
        }
        return .term
    }

    private func requestNetwork(
        payload: [String: Any],
        command: ExtensionCommand,
        requestID: String?,
        onProgress: ExtensionProcessJobManager.ProgressHandler?
    ) async -> ExtensionCapabilityResult {
        guard let rawURL = payload["url"] as? String,
            let url = URL(string: rawURL),
            let host = url.host?.lowercased(),
            ["http", "https"].contains(url.scheme?.lowercased()),
            command.networkDomains.contains(where: { domainMatches(host: host, scope: $0) })
        else {
            return .denied("network.request requires an allowed declared domain.")
        }

        var request = URLRequest(url: url)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.httpMethod = (payload["method"] as? String ?? "GET").uppercased()
        guard ["GET", "HEAD", "POST", "PUT", "PATCH", "DELETE"].contains(request.httpMethod ?? "GET") else {
            return .denied("Unsupported HTTP method.")
        }
        if let headers = payload["headers"] as? [String: Any] {
            for (key, value) in headers {
                guard key.count <= 128, let value = value as? String, value.count <= 4096 else {
                    return .denied("Invalid request headers.")
                }
                request.setValue(value, forHTTPHeaderField: key)
            }
        }
        if let body = payload["body"] as? String {
            guard body.utf8.count <= 4 * 1024 * 1024 else { return .denied("Request body exceeds the 4 MB limit.") }
            request.httpBody = body.data(using: .utf8)
        }
        if let bodyBase64 = payload["bodyBase64"] as? String,
            let data = Data(base64Encoded: bodyBase64), data.count <= 4 * 1024 * 1024
        {
            request.httpBody = data
        }
        request.timeoutInterval = min(max(payload["timeout"] as? Double ?? 30, 0.1), 120)

        do {
            let (data, response) = try await networkSession.data(for: request)
            guard data.count <= 8 * 1024 * 1024 else {
                return .denied("Network response exceeds the 8 MB limit.")
            }
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            let headers =
                (response as? HTTPURLResponse)?.allHeaderFields.reduce(into: [String: String]()) { result, entry in
                    result[String(describing: entry.key)] = String(describing: entry.value)
                } ?? [:]
            if payload["stream"] as? Bool == true, let onProgress {
                let chunkSize = 64 * 1024
                var offset = 0
                while offset < data.count {
                    let end = min(offset + chunkSize, data.count)
                    let chunk = data[offset..<end]
                    onProgress([
                        "type": "capabilityProgress",
                        "requestID": requestID ?? "network-request",
                        "capability": "network.request",
                        "stream": "body",
                        "chunk": String(decoding: chunk, as: UTF8.self),
                        "done": false,
                    ])
                    offset = end
                }
                onProgress([
                    "type": "capabilityProgress",
                    "requestID": requestID ?? "network-request",
                    "capability": "network.request",
                    "stream": "body",
                    "done": true,
                    "status": status,
                ])
            }
            audit(capability: "network.request", command: command, outcome: "status-" + String(status))
            return .success(
                AnySendable(value: [
                    "status": status,
                    "headers": headers,
                    "body": String(decoding: data, as: UTF8.self),
                    "bodyBase64": data.base64EncodedString(),
                ]))
        } catch {
            audit(capability: "network.request", command: command, outcome: "failed")
            return .denied(error.localizedDescription)
        }
    }

    private func domainMatches(host: String, scope: String) -> Bool {
        let normalized = scope.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized.hasPrefix("*.") {
            let suffix = String(normalized.dropFirst(2))
            return host == suffix || host.hasSuffix("." + suffix)
        }
        return host == normalized
    }

    private func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    private func encoded<T: Encodable>(_ value: T) -> ExtensionCapabilityResult {
        guard let data = try? JSONEncoder().encode(value),
            let object = try? JSONSerialization.jsonObject(with: data)
        else { return .denied("The capability returned an invalid JSON value.") }
        return .success(AnySendable(value: object))
    }

    private func audit(capability: String, command: ExtensionCommand, outcome: String) {
        let record: [String: Any] = [
            "capability": capability,
            "extension": command.extensionName,
            "outcome": outcome,
            "timestamp": ISO8601DateFormatter().string(from: Date()),
        ]
        guard let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        do {
            try FileManager.default.createDirectory(
                at: auditURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            var existing = (try? Data(contentsOf: auditURL)) ?? Data()
            existing.append(data)
            existing.append(0x0A)
            if existing.count > 256 * 1024 {
                existing = Data(existing.suffix(256 * 1024))
            }
            try existing.write(to: auditURL, options: [.atomic])
        } catch {
            return
        }
    }
}
