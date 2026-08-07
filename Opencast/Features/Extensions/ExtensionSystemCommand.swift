import Foundation

struct ExtensionCommandResult: Sendable {
    let stdout: String
    let stderr: String
    let status: Int32
    let timedOut: Bool
}

enum ExtensionProviderError: LocalizedError, Sendable {
    case commandFailed(path: String, status: Int32, stderr: String)
    case commandTimedOut(path: String)
    case invalidOutput(String)
    case invalidProcessID
    case protectedProcess
    case operationFailed(String)

    var errorDescription: String? {
        switch self {
        case .commandFailed(let path, let status, let stderr):
            let suffix = stderr.isEmpty ? "" : " (stderr)"
            return path + " failed with status " + String(status) + "." + suffix
        case .commandTimedOut(let path): return path + " timed out."
        case .invalidOutput(let message): return message
        case .invalidProcessID: return "The process ID is invalid."
        case .protectedProcess: return "This process is protected."
        case .operationFailed(let message): return message
        }
    }
}

private final class ExtensionDataBox: @unchecked Sendable {
    let lock = NSLock()
    var data = Data()
}

enum ExtensionFixedCommand {
    static let defaultTimeout: TimeInterval = 5
    static let defaultOutputLimit = 512 * 1024

    static func run(
        path: String,
        arguments: [String],
        timeout: TimeInterval = defaultTimeout,
        input: Data? = nil,
        outputLimit: Int = defaultOutputLimit,
        environment: [String: String]? = nil
    ) async throws -> ExtensionCommandResult {
        try await Task.detached(priority: .utility) {
            try runSynchronously(
                path: path,
                arguments: arguments,
                timeout: timeout,
                input: input,
                outputLimit: outputLimit,
                environment: environment
            )
        }.value
    }

    private static func runSynchronously(
        path: String,
        arguments: [String],
        timeout: TimeInterval,
        input: Data?,
        outputLimit: Int,
        environment: [String: String]?
    ) throws -> ExtensionCommandResult {
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        if let environment {
            process.environment = ProcessInfo.processInfo.environment.merging(environment) { _, new in new
            }
        }
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if input != nil { process.standardInput = Pipe() }
        try process.run()

        if let input, let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write(input)
            inputPipe.fileHandleForWriting.closeFile()
        }

        let group = DispatchGroup()
        let stdoutBox = ExtensionDataBox()
        let stderrBox = ExtensionDataBox()

        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = outputPipe.fileHandleForReading.readDataToEndOfFile()
            stdoutBox.lock.lock()
            stdoutBox.data = data
            stdoutBox.lock.unlock()
            group.leave()
        }
        group.enter()
        DispatchQueue.global(qos: .utility).async {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            stderrBox.lock.lock()
            stderrBox.data = data
            stderrBox.lock.unlock()
            group.leave()
        }

        let deadline = Date().addingTimeInterval(max(0.1, timeout))
        while process.isRunning, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.02)
        }

        let timedOut = process.isRunning
        if timedOut {
            process.terminate()
            Thread.sleep(forTimeInterval: 0.1)
            if process.isRunning {
                kill(process.processIdentifier, SIGKILL)
            }
        }
        process.waitUntilExit()
        group.wait()

        let stdout = stdoutBox.data
        let stderr = stderrBox.data
        let boundedStdout = stdout.prefix(max(0, outputLimit))
        let boundedStderr = stderr.prefix(max(0, outputLimit))
        return ExtensionCommandResult(
            stdout: String(decoding: boundedStdout, as: UTF8.self),
            stderr: String(decoding: boundedStderr, as: UTF8.self),
            status: process.terminationStatus,
            timedOut: timedOut
        )
    }
}
