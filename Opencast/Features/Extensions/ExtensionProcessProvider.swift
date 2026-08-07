import Darwin
import Foundation

enum ExtensionProcessSignal: Int32, Codable, Sendable {
    case term = 15
    case kill = 9
}

struct ExtensionProcessInfo: Codable, Equatable, Identifiable, Sendable {
    let pid: Int32
    let parentPID: Int32
    let user: String
    let cpuPercent: Double
    let memoryPercent: Double
    let name: String
    let path: String?

    var id: Int32 { pid }
}

struct ExtensionProcessTermination: Codable, Equatable, Sendable {
    let signal: ExtensionProcessSignal
    let terminatedPIDs: [Int32]
}

actor ExtensionProcessProvider {
    private let protectedPIDs: Set<Int32>

    init(protectedPIDs: Set<Int32> = []) {
        self.protectedPIDs = protectedPIDs
    }

    func snapshot() async throws -> [ExtensionProcessInfo] {
        let result = try await ExtensionFixedCommand.run(
            path: "/bin/ps",
            arguments: ["-axo", "pid=,ppid=,user=,%cpu=,%mem=,command="],
            timeout: 3
        )
        guard !result.timedOut else { throw ExtensionProviderError.commandTimedOut(path: "/bin/ps") }
        guard result.status == 0 else {
            throw ExtensionProviderError.commandFailed(path: "/bin/ps", status: result.status, stderr: result.stderr)
        }
        return try Self.parse(result.stdout)
    }

    func terminate(
        pid: Int32,
        signal: ExtensionProcessSignal,
        includeDescendants: Bool
    ) async throws -> ExtensionProcessTermination {
        guard pid > 1 else { throw ExtensionProviderError.invalidProcessID }
        guard !protectedPIDs.contains(pid) else { throw ExtensionProviderError.protectedProcess }

        let targets: [Int32]
        if includeDescendants {
            let processes = try await snapshot()
            targets = Self.treeTargets(root: pid, processes: processes)
        } else {
            targets = [pid]
        }

        let protectedPIDs = self.protectedPIDs
        let result = await Task.detached(priority: .userInitiated) {
            var terminated: [Int32] = []
            var failures: [String] = []
            for target in targets {
                if protectedPIDs.contains(target) { continue }
                if Darwin.kill(target, signal.rawValue) == 0 {
                    terminated.append(target)
                } else {
                    failures.append("PID " + String(target) + ": " + String(cString: strerror(errno)))
                }
            }
            return (terminated: terminated, failures: failures)
        }.value

        if result.terminated.isEmpty {
            throw ExtensionProviderError.operationFailed(
                result.failures.first ?? "The process could not be terminated."
            )
        }
        return ExtensionProcessTermination(signal: signal, terminatedPIDs: result.terminated)
    }

    func restart(pid: Int32, force: Bool) async throws -> Bool {
        let processes = try await snapshot()
        guard let process = processes.first(where: { $0.pid == pid }), let path = process.path else {
            throw ExtensionProviderError.operationFailed("The process executable could not be resolved.")
        }
        _ = try await terminate(pid: pid, signal: force ? .kill : .term, includeDescendants: false)
        let relaunched = Process()
        relaunched.executableURL = URL(fileURLWithPath: path)
        try relaunched.run()
        return true
    }

    private nonisolated static func parse(_ output: String) throws -> [ExtensionProcessInfo] {
        var processes: [ExtensionProcessInfo] = []
        for line in output.split(whereSeparator: \.isNewline) {
            let fields = line.split(maxSplits: 5, whereSeparator: { $0 == " " || $0 == "\t" })
            guard fields.count == 6,
                let pid = Int32(fields[0]),
                let parentPID = Int32(fields[1]),
                let cpu = Double(fields[3]),
                let memory = Double(fields[4])
            else { continue }
            let command = String(fields[5])
            let commandToken = command.split(separator: " ", maxSplits: 1).first.map(String.init) ?? command
            let path = commandToken.hasPrefix("/") ? commandToken : nil
            let name = path.map { URL(fileURLWithPath: $0).lastPathComponent } ?? commandToken
            processes.append(
                ExtensionProcessInfo(
                    pid: pid,
                    parentPID: parentPID,
                    user: String(fields[2]),
                    cpuPercent: cpu,
                    memoryPercent: memory,
                    name: name,
                    path: path
                )
            )
        }
        guard !processes.isEmpty || output.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw ExtensionProviderError.invalidOutput("The process list could not be parsed.")
        }
        return processes
    }

    private nonisolated static func treeTargets(
        root: Int32,
        processes: [ExtensionProcessInfo]
    ) -> [Int32] {
        var children: [Int32: [Int32]] = [:]
        for process in processes {
            children[process.parentPID, default: []].append(process.pid)
        }

        var result: [(pid: Int32, depth: Int)] = []
        var queue: [(Int32, Int)] = [(root, 0)]
        var visited: Set<Int32> = []
        while let (pid, depth) = queue.popLast() {
            guard visited.insert(pid).inserted else { continue }
            result.append((pid, depth))
            for child in children[pid, default: []] {
                queue.append((child, depth + 1))
            }
        }
        return result.sorted { $0.depth > $1.depth }.map(\.pid)
    }
}
