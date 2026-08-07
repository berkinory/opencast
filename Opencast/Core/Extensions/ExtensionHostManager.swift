import Foundation
import Combine
import Darwin

@MainActor
final class ExtensionHostManager: ObservableObject {
    @Published private(set) var snapshot: ExtensionRenderSnapshot?
    @Published private(set) var isRunning = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var lastMetrics: ExtensionRuntimeMetrics?
    @Published private(set) var actionProgress: ExtensionCapabilityProgress?
    @Published private(set) var feedback: ExtensionFeedback?
    var onNoViewFinished: (() -> Void)?

    private let capabilityBroker: ExtensionCapabilityBroker
    private let showHUD: (String, String?, String?) -> Void
    private let confirmAction: (String, String, String) -> Bool
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()
    private var command: ExtensionCommand?
    private var requestCounter = 0
    private var watchdogTask: Task<Void, Never>?

    init(
        capabilityBroker: ExtensionCapabilityBroker,
        showHUD: @escaping (String, String?, String?) -> Void,
        confirmAction: @escaping (String, String, String) -> Bool
    ) {
        self.capabilityBroker = capabilityBroker
        self.showHUD = showHUD
        self.confirmAction = confirmAction
    }

    func start(_ command: ExtensionCommand) {
        stop()
        guard let executable = hostExecutableURL() else {
            errorMessage = "Extension host is not available."
            return
        }

        let process = Process()
        let inputPipe = Pipe()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = executable
        process.arguments = ["--stdio"]
        process.standardInput = inputPipe
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        process.terminationHandler = { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.hostTerminated()
            }
        }

        let stdout = outputPipe.fileHandleForReading
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.consume(data)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in
            _ = handle.availableData
        }

        do {
            try process.run()
        } catch {
            errorMessage = "Could not start extension host: \(error.localizedDescription)"
            return
        }

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = stdout
        self.command = command
        snapshot = nil
        errorMessage = nil
        lastMetrics = nil
        actionProgress = nil
        feedback = nil
        isRunning = true
        armWatchdog()
        send([
            "type": "launch",
            "requestID": nextRequestID(prefix: "launch"),
            "bundlePath": command.bundleURL.path,
            "mode": command.mode,
            "commandName": command.id.split(separator: ":").last.map(String.init) ?? command.id,
            "extensionName": command.extensionName,
            "launchType": "userInitiated",
            "supportPath": command.bundleURL.deletingLastPathComponent().path,
            "assetsPath": command.bundleURL.appendingPathComponent("assets", isDirectory: true).path,
            "preferences": preferenceValues(for: command),
        ])
    }

    func stop() {
        watchdogTask?.cancel()
        watchdogTask = nil
        if let output { output.readabilityHandler = nil }
        process?.terminationHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
        command = nil
        outputBuffer.removeAll(keepingCapacity: false)
        snapshot = nil
        isRunning = false
        actionProgress = nil
        feedback = nil
    }

    func select(itemID: String) {
        armWatchdog()
        send([
            "type": "event",
            "requestID": nextRequestID(prefix: "selection"),
            "event": "selectionChanged",
            "itemID": itemID,
        ])
    }

    func search(text: String) {
        armWatchdog()
        send([
            "type": "event",
            "requestID": nextRequestID(prefix: "search"),
            "event": "searchChanged",
            "text": text,
        ])
    }

    func loadMore(root: String = "list") {
        armWatchdog(duration: 60)
        send([
            "type": "event",
            "requestID": nextRequestID(prefix: "load-more"),
            "event": "loadMore",
            "root": root,
        ])
    }

    func invoke(actionID: String, itemID: String?, fields: [String: String]? = nil) {
        armWatchdog()
        actionProgress = nil
        var message: [String: Any] = [
            "type": "event",
            "requestID": nextRequestID(prefix: "action"),
            "event": "actionInvoked",
            "actionID": actionID,
        ]
        if let itemID { message["itemID"] = itemID }
        if let fields { message["fields"] = fields }
        send(message)
    }

    func changeDropdown(id: String, value: String) {
        armWatchdog()
        send([
            "type": "event",
            "requestID": nextRequestID(prefix: "dropdown"),
            "event": "dropdownChanged",
            "dropdownID": id,
            "value": value,
        ])
    }

    func changeField(id: String, value: String) {
        armWatchdog()
        send([
            "type": "event",
            "requestID": nextRequestID(prefix: "field"),
            "event": "formChanged",
            "fieldID": id,
            "value": value,
        ])
    }

    func invokePrimary(for itemID: String) {
        guard let action = snapshot?.items.first(where: { $0.id == itemID })?.actions.first else { return }
        invoke(actionID: action.id, itemID: itemID)
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while outputBuffer.count >= 4 {
            let length = outputBuffer.prefix(4).reduce(UInt32(0)) { partial, byte in
                (partial << 8) | UInt32(byte)
            }
            let frameLength = Int(length)
            guard frameLength <= 4 * 1024 * 1024 else {
                errorMessage = "Extension host sent an oversized frame."
                stop()
                return
            }
            guard outputBuffer.count >= frameLength + 4 else { return }
            let payload = outputBuffer.subdata(in: 4..<(frameLength + 4))
            outputBuffer.removeSubrange(0..<(frameLength + 4))
            handle(payload)
        }
    }

    private func handle(_ data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data),
            let message = object as? [String: Any],
            let type = message["type"] as? String
        else {
            errorMessage = "Extension host sent invalid JSON."
            return
        }

        switch type {
        case "render":
            guard let snapshotData = try? JSONSerialization.data(withJSONObject: message),
                let decoded = try? JSONDecoder().decode(ExtensionRenderSnapshot.self, from: snapshotData)
            else {
                errorMessage = "Extension returned an invalid render snapshot."
                return
            }
            snapshot = decoded
            cancelWatchdog()
        case "capabilityRequest":
            handleCapabilityRequest(message)
        case "capabilityProgress":
            if let data = try? JSONSerialization.data(withJSONObject: message),
                let progress = try? JSONDecoder().decode(ExtensionCapabilityProgress.self, from: data)
            {
                actionProgress = progress.done ? nil : progress
            }
            armWatchdog(duration: 60)
        case "feedback":
            let kind = message["feedback"] as? String ?? "toast"
            if kind == "hud" {
                guard let hudMessage = message["message"] as? String else { return }
                showHUD(
                    hudMessage, message["toastID"] as? String, message["style"] as? String)
                feedback = nil
            } else if kind == "confirm", let requestID = message["requestID"] as? String {
                let confirmed = confirmAction(
                    message["title"] as? String ?? "Confirm",
                    message["message"] as? String ?? "Are you sure?",
                    message["primaryAction"] as? String ?? "Continue")
                send([
                    "type": "event",
                    "event": "confirmResponse",
                    "requestID": requestID,
                    "confirmed": confirmed,
                ])
                feedback = nil
            } else if kind == "toastHide" {
                feedback = nil
            } else if kind == "toastShow" {
                if let current = feedback {
                    feedback = ExtensionFeedback(
                        id: current.id,
                        kind: "toast",
                        title: current.title,
                        message: current.message,
                        style: current.style
                    )
                }
            } else {
                let current = feedback
                feedback = ExtensionFeedback(
                    id: message["toastID"] as? String ?? current?.id ?? UUID().uuidString,
                    kind: kind == "toastUpdate" ? "toast" : kind,
                    title: message["title"] as? String ?? current?.title,
                    message: message["message"] as? String ?? current?.message,
                    style: message["style"] as? String ?? current?.style
                )
            }
        case "error":
            errorMessage = message["message"] as? String ?? "Extension failed."
        case "dispose":
            isRunning = false
            watchdogTask?.cancel()
            watchdogTask = nil
            if let command, let metrics = message["metrics"] as? [String: Any],
                let durationMS = metrics["durationMS"] as? Int
            {
                lastMetrics = ExtensionRuntimeMetrics(
                    commandID: command.id,
                    durationMS: durationMS,
                    peakResidentBytes: metrics["peakResidentBytes"] as? Int,
                    reason: message["reason"] as? String ?? "closed",
                    timestamp: Date()
                )
            }
            snapshot = nil
            actionProgress = nil
            if command?.mode == "no-view" {
                onNoViewFinished?()
            }
        case "log":
            break
        default:
            break
        }
    }

    private func handleCapabilityRequest(_ message: [String: Any]) {
        guard let requestID = message["requestID"] as? String,
            let capability = message["capability"] as? String,
            let command
        else { return }
        let payload = message["payload"] as? [String: Any] ?? [:]
        let isStreaming = ((payload["options"] as? [String: Any])?["stream"] as? Bool) == true
        if isStreaming { armWatchdog(duration: 60) }
        Task { @MainActor [weak self] in
            guard let self else { return }
            let result = await capabilityBroker.handle(
                capability: capability,
                payload: payload,
                command: command,
                requestID: requestID,
                onProgress: { [weak self] event in
                    self?.send(event)
                }
            )
            var response: [String: Any] = [
                "type": "capabilityResponse",
                "requestID": requestID,
                "ok": result.ok,
            ]
            if let value = result.value?.value { response["value"] = value }
            if let error = result.error { response["error"] = error }
            self.send(response)
        }
    }

    private func send(_ message: [String: Any]) {
        guard let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
            data.count <= 4 * 1024 * 1024
        else { return }
        var length = UInt32(data.count).bigEndian
        var frame = Data(bytes: &length, count: 4)
        frame.append(data)
        input?.write(frame)
    }

    private func nextRequestID(prefix: String) -> String {
        requestCounter += 1
        return "\(prefix)-\(requestCounter)"
    }

    private func preferenceValues(for command: ExtensionCommand) -> [String: Any] {
        capabilityBroker.preferenceValues(for: command)
    }

    private func hostTerminated() {
        cancelWatchdog()
        isRunning = false
        process = nil
        input = nil
        output = nil
    }

    private func armWatchdog(duration: TimeInterval = 12) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled, self.isRunning else { return }
            self.errorMessage = "Extension host exceeded its wall-clock budget."
            guard let process = self.process else { return }
            process.terminate()
            try? await Task.sleep(for: .milliseconds(250))
            if process.isRunning { kill(process.processIdentifier, SIGKILL) }
        }
    }

    private func cancelWatchdog() {
        watchdogTask?.cancel()
        watchdogTask = nil
    }

    private func hostExecutableURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["OPENCAST_EXTENSION_HOST"] {
            return URL(fileURLWithPath: override)
        }
        let bundled = Bundle.main.bundleURL
            .appendingPathComponent("Contents", isDirectory: true)
            .appendingPathComponent("Helpers", isDirectory: true)
            .appendingPathComponent("OpencastExtensionHost")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/ExtensionHostDerived/Build/Products/Debug/OpencastExtensionHost")
        return FileManager.default.isExecutableFile(atPath: development.path) ? development : nil
    }
}
