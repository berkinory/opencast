import Darwin
import Foundation

struct ExtensionProcessJobStart: Codable, Sendable {
    let jobID: String
}

@MainActor
final class ExtensionProcessJobManager {
    typealias ProgressHandler = ([String: Any]) -> Void

    private final class Job: @unchecked Sendable {
        let id: String
        let process: Process
        let outputPipe: Pipe
        let errorPipe: Pipe
        let owner: String
        let requestID: String
        let progress: ProgressHandler
        var outputBytes = 0
        var timedOut = false
        var cancelled = false
        var timeoutTask: Task<Void, Never>?

        init(
            id: String,
            process: Process,
            outputPipe: Pipe,
            errorPipe: Pipe,
            owner: String,
            requestID: String,
            progress: @escaping ProgressHandler
        ) {
            self.id = id
            self.process = process
            self.outputPipe = outputPipe
            self.errorPipe = errorPipe
            self.owner = owner
            self.requestID = requestID
            self.progress = progress
        }
    }

    private static let outputLimit = 256 * 1024
    private var jobs: [String: Job] = [:]
    private var nextID = 0

    func start(
        path: String,
        arguments: [String],
        input: Data?,
        timeout: TimeInterval,
        owner: String,
        requestID: String,
        progress: @escaping ProgressHandler
    ) throws -> ExtensionProcessJobStart {
        nextID += 1
        let jobID = owner + "-job-" + String(nextID) + "-" + UUID().uuidString
        let process = Process()
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.executableURL = URL(fileURLWithPath: path)
        process.arguments = arguments
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        if input != nil { process.standardInput = Pipe() }

        let job = Job(
            id: jobID,
            process: process,
            outputPipe: outputPipe,
            errorPipe: errorPipe,
            owner: owner,
            requestID: requestID,
            progress: progress
        )
        outputPipe.fileHandleForReading.readabilityHandler = { [weak self, weak job] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.emit(data: data, stream: "stdout", job: job)
            }
        }
        errorPipe.fileHandleForReading.readabilityHandler = { [weak self, weak job] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            Task { @MainActor in
                self?.emit(data: data, stream: "stderr", job: job)
            }
        }
        process.terminationHandler = { [weak self, weak job] _ in
            Task { @MainActor in
                self?.finish(job: job)
            }
        }

        try process.run()
        jobs[jobID] = job
        if let input, let inputPipe = process.standardInput as? Pipe {
            inputPipe.fileHandleForWriting.write(input)
            inputPipe.fileHandleForWriting.closeFile()
        }
        job.timeoutTask = Task { @MainActor [weak self, weak job] in
            try? await Task.sleep(for: .seconds(timeout))
            guard let self, let job, !Task.isCancelled, job.process.isRunning else { return }
            job.timedOut = true
            job.process.terminate()
            try? await Task.sleep(for: .milliseconds(100))
            if job.process.isRunning { kill(job.process.processIdentifier, SIGKILL) }
            self.finish(job: job)
        }
        return ExtensionProcessJobStart(jobID: jobID)
    }

    func cancel(jobID: String, owner: String) -> Bool {
        guard let job = jobs[jobID] else { return false }
        guard job.owner == owner else { return false }
        job.cancelled = true
        if job.process.isRunning {
            job.process.terminate()
            Task { @MainActor [weak self, weak job] in
                try? await Task.sleep(for: .milliseconds(100))
                guard let self, let job, self.jobs[job.id] != nil else { return }
                if job.process.isRunning { kill(job.process.processIdentifier, SIGKILL) }
                self.finish(job: job)
            }
        } else {
            finish(job: job)
        }
        return true
    }

    private func emit(data: Data, stream: String, job: Job?) {
        guard let job, jobs[job.id] != nil else { return }
        let remaining = Self.outputLimit - job.outputBytes
        guard remaining > 0 else { return }
        let chunk = data.prefix(remaining)
        job.outputBytes += chunk.count
        job.progress([
            "type": "capabilityProgress",
            "requestID": job.requestID,
            "capability": "process.execute",
            "jobID": job.id,
            "stream": stream,
            "chunk": String(decoding: chunk, as: UTF8.self),
            "truncated": chunk.count < data.count,
            "done": false,
        ])
    }

    private func finish(job: Job?) {
        guard let job, !job.process.isRunning, jobs.removeValue(forKey: job.id) != nil else { return }
        job.timeoutTask?.cancel()
        job.outputPipe.fileHandleForReading.readabilityHandler = nil
        job.errorPipe.fileHandleForReading.readabilityHandler = nil
        let status = job.process.terminationStatus
        job.progress([
            "type": "capabilityProgress",
            "requestID": job.requestID,
            "capability": "process.execute",
            "jobID": job.id,
            "status": status,
            "timedOut": job.timedOut,
            "cancelled": job.cancelled,
            "done": true,
        ])
    }
}
