import Foundation

struct ExtensionPortInfo: Codable, Equatable, Identifiable, Sendable {
    let pid: Int32
    let processName: String
    let user: String?
    let host: String
    let port: Int
    let protocolName: String

    var id: String { "\(pid):\(protocolName):\(host):\(port)" }
}

actor ExtensionPortProvider {
    func snapshot() async throws -> [ExtensionPortInfo] {
        let result = try await ExtensionFixedCommand.run(
            path: "/usr/sbin/lsof",
            arguments: ["-nP", "-iTCP", "-sTCP:LISTEN", "-F", "pcunP"],
            timeout: 5
        )
        guard !result.timedOut else { throw ExtensionProviderError.commandTimedOut(path: "/usr/sbin/lsof") }
        guard result.status == 0 || result.status == 1 else {
            throw ExtensionProviderError.commandFailed(
                path: "/usr/sbin/lsof", status: result.status, stderr: result.stderr
            )
        }
        return Self.parse(result.stdout)
    }

    private nonisolated static func parse(_ output: String) -> [ExtensionPortInfo] {
        var currentPID: Int32?
        var currentName: String?
        var currentUser: String?
        var currentProtocol = "TCP"
        var ports: [ExtensionPortInfo] = []

        func appendEndpoint(_ endpoint: String) {
            guard let pid = currentPID, let port = Self.port(from: endpoint), !endpoint.isEmpty else { return }
            let host = Self.host(from: endpoint)
            ports.append(
                ExtensionPortInfo(
                    pid: pid,
                    processName: currentName ?? "Unknown",
                    user: currentUser,
                    host: host,
                    port: port,
                    protocolName: currentProtocol
                )
            )
        }

        for record in output.split(whereSeparator: \.isNewline) {
            guard let kind = record.first else { continue }
            let value = String(record.dropFirst())
            switch kind {
            case "p":
                currentPID = Int32(value)
                currentName = nil
                currentUser = nil
                currentProtocol = "TCP"
            case "c": currentName = value
            case "u": currentUser = value
            case "P": currentProtocol = value
            case "n": appendEndpoint(value)
            default: break
            }
        }
        return ports
    }

    private nonisolated static func port(from endpoint: String) -> Int? {
        let value = endpoint.hasSuffix("]") ? endpoint : endpoint
        guard let separator = value.lastIndex(of: ":") else { return nil }
        return Int(value[value.index(after: separator)...])
    }

    private nonisolated static func host(from endpoint: String) -> String {
        guard let separator = endpoint.lastIndex(of: ":") else { return endpoint }
        let rawHost = String(endpoint[..<separator])
        if rawHost.hasPrefix("[") && rawHost.hasSuffix("]") {
            return String(rawHost.dropFirst().dropLast())
        }
        return rawHost
    }
}
