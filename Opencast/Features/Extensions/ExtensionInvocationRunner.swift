import Foundation
import Combine

@MainActor
final class ExtensionInvocationRunner {
    private let command: ExtensionCommand
    private let capabilityBroker: ExtensionCapabilityBroker
    private let onRender: (ExtensionRenderSnapshot) -> Void
    private let onFinish: (ExtensionRuntimeMetrics?, String?) -> Void
    private var process: Process?
    private var input: FileHandle?
    private var output: FileHandle?
    private var outputBuffer = Data()
    private var requestCounter = 0
    private var watchdogTask: Task<Void, Never>?
    private var finished = false

    init(
        command: ExtensionCommand,
        capabilityBroker: ExtensionCapabilityBroker,
        onRender: @escaping (ExtensionRenderSnapshot) -> Void,
        onFinish: @escaping (ExtensionRuntimeMetrics?, String?) -> Void
    ) {
        self.command = command
        self.capabilityBroker = capabilityBroker
        self.onRender = onRender
        self.onFinish = onFinish
    }

    func start() {
        guard let executable = hostExecutableURL() else {
            finish(metrics: nil, error: "Extension host is not available.")
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
            Task { @MainActor [weak self] in self?.finish(metrics: nil, error: nil) }
        }

        let stdout = outputPipe.fileHandleForReading
        stdout.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor [weak self] in self?.consume(data) }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { handle in _ = handle.availableData }

        do {
            try process.run()
        } catch {
            finish(metrics: nil, error: error.localizedDescription)
            return
        }

        self.process = process
        input = inputPipe.fileHandleForWriting
        output = stdout
        armWatchdog(duration: 10)
        send([
            "type": "launch",
            "requestID": nextRequestID(prefix: "background-launch"),
            "bundlePath": command.bundleURL.path,
            "mode": command.mode,
            "background": true,
            "commandName": command.id.split(separator: ":").last.map(String.init) ?? command.id,
            "extensionName": command.extensionName,
            "launchType": "background",
            "supportPath": command.bundleURL.deletingLastPathComponent().path,
            "assetsPath": command.bundleURL.appendingPathComponent("assets", isDirectory: true).path,
            "preferences": capabilityBroker.preferenceValues(for: command),
        ])
    }

    func cancel() {
        finish(metrics: nil, error: "Background extension was cancelled.")
    }

    private func consume(_ data: Data) {
        outputBuffer.append(data)
        while outputBuffer.count >= 4 {
            let length = outputBuffer.prefix(4).reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
            let frameLength = Int(length)
            guard frameLength <= 4 * 1024 * 1024 else {
                finish(metrics: nil, error: "Background extension sent an oversized frame.")
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
            let message = object as? [String: Any], let type = message["type"] as? String
        else {
            finish(metrics: nil, error: "Background extension sent invalid JSON.")
            return
        }

        switch type {
        case "render":
            guard let snapshotData = try? JSONSerialization.data(withJSONObject: message),
                let snapshot = try? JSONDecoder().decode(ExtensionRenderSnapshot.self, from: snapshotData)
            else {
                finish(metrics: nil, error: "Background extension returned an invalid snapshot.")
                return
            }
            onRender(snapshot)
        case "capabilityRequest":
            handleCapabilityRequest(message)
        case "capabilityProgress":
            armWatchdog(duration: 60)
        case "dispose":
            let metrics = parseMetrics(message)
            finish(metrics: metrics, error: nil)
        case "error":
            finish(metrics: nil, error: message["message"] as? String ?? "Background extension failed.")
        default:
            break
        }
    }

    private func handleCapabilityRequest(_ message: [String: Any]) {
        guard let requestID = message["requestID"] as? String,
            let capability = message["capability"] as? String
        else { return }
        let payload = message["payload"] as? [String: Any] ?? [:]
        let isStreaming = ((payload["options"] as? [String: Any])?["stream"] as? Bool) == true
        if isStreaming { armWatchdog(duration: 60) }
        Task { @MainActor [weak self] in
            guard let self, !self.finished else { return }
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
                "type": "capabilityResponse", "requestID": requestID, "ok": result.ok,
            ]
            if let value = result.value?.value { response["value"] = value }
            if let error = result.error { response["error"] = error }
            self.send(response)
        }
    }

    private func parseMetrics(_ message: [String: Any]) -> ExtensionRuntimeMetrics? {
        guard let raw = message["metrics"] as? [String: Any], let durationMS = raw["durationMS"] as? Int else {
            return nil
        }
        return ExtensionRuntimeMetrics(
            commandID: command.id,
            durationMS: durationMS,
            peakResidentBytes: raw["peakResidentBytes"] as? Int,
            reason: message["reason"] as? String ?? "completed",
            timestamp: Date()
        )
    }

    private func armWatchdog(duration: TimeInterval) {
        watchdogTask?.cancel()
        watchdogTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(duration))
            guard let self, !Task.isCancelled, !self.finished else { return }
            self.finish(metrics: nil, error: "Background extension exceeded its wall-clock budget.")
        }
    }

    private func finish(metrics: ExtensionRuntimeMetrics?, error: String?) {
        guard !finished else { return }
        finished = true
        watchdogTask?.cancel()
        watchdogTask = nil
        output?.readabilityHandler = nil
        if process?.isRunning == true { process?.terminate() }
        try? input?.close()
        try? output?.close()
        process = nil
        input = nil
        output = nil
        onFinish(metrics, error)
    }

    private func send(_ message: [String: Any]) {
        guard !finished, let data = try? JSONSerialization.data(withJSONObject: message, options: [.sortedKeys]),
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

    private func hostExecutableURL() -> URL? {
        if let override = ProcessInfo.processInfo.environment["OPENCAST_EXTENSION_HOST"] {
            return URL(fileURLWithPath: override)
        }
        let bundled = Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/OpencastExtensionHost")
        if FileManager.default.isExecutableFile(atPath: bundled.path) { return bundled }
        let development = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("build/ExtensionHostDerived/Build/Products/Debug/OpencastExtensionHost")
        return FileManager.default.isExecutableFile(atPath: development.path) ? development : nil
    }
}
