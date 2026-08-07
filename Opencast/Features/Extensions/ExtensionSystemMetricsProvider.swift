import Darwin
import Foundation

struct ExtensionSystemMetricsSnapshot: Codable, Equatable, Sendable {
    let cpuPercent: Double
    let memoryUsedBytes: UInt64
    let memoryTotalBytes: UInt64
    let diskUsedBytes: UInt64
    let diskTotalBytes: UInt64
    let batteryPercent: Double?
    let isCharging: Bool?
    let networkDownloadBytesPerSecond: Double
    let networkUploadBytesPerSecond: Double
    let temperatureCelsius: Double?
    let sampledAt: Date

    var memoryPercent: Double {
        guard memoryTotalBytes > 0 else { return 0 }
        return Double(memoryUsedBytes) / Double(memoryTotalBytes) * 100
    }

    var diskPercent: Double {
        guard diskTotalBytes > 0 else { return 0 }
        return Double(diskUsedBytes) / Double(diskTotalBytes) * 100
    }
}

actor ExtensionSystemMetricsProvider {
    private var previous: RawMetrics?
    private var previousSampleDate: Date?

    func snapshot(now: Date = Date()) async -> ExtensionSystemMetricsSnapshot {
        var raw = await Task.detached(priority: .utility) {
            await Self.readRawMetrics()
        }.value
        var sampleDate = now

        if previous == nil {
            previous = raw
            previousSampleDate = now
            try? await Task.sleep(for: .milliseconds(100))
            raw = await Task.detached(priority: .utility) {
                await Self.readRawMetrics()
            }.value
            sampleDate = Date()
        }

        let interval = max(0.1, previousSampleDate.map { sampleDate.timeIntervalSince($0) } ?? 0)
        let cpuPercent: Double
        if let previous, raw.cpuTotalTicks > previous.cpuTotalTicks {
            let totalDelta = raw.cpuTotalTicks - previous.cpuTotalTicks
            let idleDelta = max(0, raw.cpuIdleTicks - previous.cpuIdleTicks)
            cpuPercent = min(100, max(0, Double(totalDelta - idleDelta) / Double(totalDelta) * 100))
        } else {
            cpuPercent = 0
        }

        let downloadRate =
            previous.map {
                Double(max(0, raw.networkInputBytes - $0.networkInputBytes)) / interval
            } ?? 0
        let uploadRate =
            previous.map {
                Double(max(0, raw.networkOutputBytes - $0.networkOutputBytes)) / interval
            } ?? 0
        previous = raw
        previousSampleDate = sampleDate

        return ExtensionSystemMetricsSnapshot(
            cpuPercent: cpuPercent,
            memoryUsedBytes: raw.memoryUsedBytes,
            memoryTotalBytes: raw.memoryTotalBytes,
            diskUsedBytes: raw.diskUsedBytes,
            diskTotalBytes: raw.diskTotalBytes,
            batteryPercent: raw.batteryPercent,
            isCharging: raw.isCharging,
            networkDownloadBytesPerSecond: downloadRate,
            networkUploadBytesPerSecond: uploadRate,
            temperatureCelsius: raw.temperatureCelsius,
            sampledAt: sampleDate
        )
    }

    private struct RawMetrics: Sendable {
        let cpuTotalTicks: Int64
        let cpuIdleTicks: Int64
        let memoryUsedBytes: UInt64
        let memoryTotalBytes: UInt64
        let diskUsedBytes: UInt64
        let diskTotalBytes: UInt64
        let batteryPercent: Double?
        let isCharging: Bool?
        let networkInputBytes: UInt64
        let networkOutputBytes: UInt64
        let temperatureCelsius: Double?
    }

    private static func readRawMetrics() async -> RawMetrics {
        let cpu = readCPUTicks()
        let memory = readMemory()
        let disk = readDisk()
        let network = readNetworkBytes()
        let batteryOutput = try? await ExtensionFixedCommand.run(
            path: "/usr/bin/pmset", arguments: ["-g", "batt"], timeout: 2, outputLimit: 16 * 1024)
        let thermalOutput = try? await ExtensionFixedCommand.run(
            path: "/usr/bin/pmset", arguments: ["-g", "therm"], timeout: 2, outputLimit: 16 * 1024)

        return RawMetrics(
            cpuTotalTicks: cpu.total,
            cpuIdleTicks: cpu.idle,
            memoryUsedBytes: memory.used,
            memoryTotalBytes: memory.total,
            diskUsedBytes: disk.used,
            diskTotalBytes: disk.total,
            batteryPercent: batteryOutput.flatMap { parseBattery(String($0.stdout))?.percent },
            isCharging: batteryOutput.flatMap { parseBattery(String($0.stdout))?.charging },
            networkInputBytes: network.input,
            networkOutputBytes: network.output,
            temperatureCelsius: thermalOutput.flatMap { parseTemperature(String($0.stdout)) }
        )
    }

    private static func readCPUTicks() -> (total: Int64, idle: Int64) {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        let result = host_processor_info(
            mach_host_self(),
            PROCESSOR_CPU_LOAD_INFO,
            &cpuCount,
            &info,
            &infoCount
        )
        guard result == KERN_SUCCESS, let info else { return (0, 0) }
        defer {
            vm_deallocate(
                mach_task_self_,
                vm_address_t(bitPattern: info),
                vm_size_t(Int(infoCount) * MemoryLayout<integer_t>.size)
            )
        }

        var total: Int64 = 0
        var idle: Int64 = 0
        let stride = Int(CPU_STATE_MAX)
        for cpu in 0..<Int(cpuCount) {
            let offset = cpu * stride
            let user = Int64(info[offset + Int(CPU_STATE_USER)])
            let system = Int64(info[offset + Int(CPU_STATE_SYSTEM)])
            let nice = Int64(info[offset + Int(CPU_STATE_NICE)])
            let cpuIdle = Int64(info[offset + Int(CPU_STATE_IDLE)])
            total += user + system + nice + cpuIdle
            idle += cpuIdle
        }
        return (total, idle)
    }

    private static func readMemory() -> (used: UInt64, total: UInt64) {
        var totalBytes: UInt64 = 0
        var totalSize = MemoryLayout<UInt64>.size
        sysctlbyname("hw.memsize", &totalBytes, &totalSize, nil, 0)

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &stats) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) { rebound in
                host_statistics64(mach_host_self(), HOST_VM_INFO64, rebound, &count)
            }
        }
        guard result == KERN_SUCCESS else { return (0, totalBytes) }
        let freePages = UInt64(stats.free_count + stats.speculative_count)
        let freeBytes = freePages * UInt64(getpagesize())
        return (totalBytes > freeBytes ? totalBytes - freeBytes : 0, totalBytes)
    }

    private static func readDisk() -> (used: UInt64, total: UInt64) {
        guard
            let attributes = try? FileManager.default.attributesOfFileSystem(forPath: NSHomeDirectory()),
            let total = (attributes[.systemSize] as? NSNumber)?.uint64Value,
            let free = (attributes[.systemFreeSize] as? NSNumber)?.uint64Value
        else { return (0, 0) }
        return (total > free ? total - free : 0, total)
    }

    private static func readNetworkBytes() -> (input: UInt64, output: UInt64) {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return (0, 0) }
        defer { freeifaddrs(addressList) }

        var input: UInt64 = 0
        var output: UInt64 = 0
        var current: UnsafeMutablePointer<ifaddrs>? = first
        while let interface = current {
            defer { current = interface.pointee.ifa_next }
            let flags = interface.pointee.ifa_flags
            guard flags & UInt32(IFF_UP) != 0,
                let name = interface.pointee.ifa_name,
                String(cString: name) != "lo0",
                let rawData = interface.pointee.ifa_data
            else { continue }
            let data = rawData.assumingMemoryBound(to: if_data.self).pointee
            input += UInt64(data.ifi_ibytes)
            output += UInt64(data.ifi_obytes)
        }
        return (input, output)
    }

    private static func parseBattery(_ output: String) -> (percent: Double, charging: Bool)? {
        guard let percentEnd = output.firstIndex(of: "%") else { return nil }
        let prefix = output[..<percentEnd]
        let digits = prefix.split(whereSeparator: { !$0.isNumber && $0 != "." }).last
        guard let digits, let percent = Double(digits) else { return nil }
        let lowercased = output.lowercased()
        return (percent, lowercased.contains("charging") && !lowercased.contains("discharging"))
    }

    private static func parseTemperature(_ output: String) -> Double? {
        let pattern = #"(\\d+(?:\\.\\d+)?)\\s*(?:C|°C)"#
        guard let expression = try? NSRegularExpression(pattern: pattern),
            let match = expression.firstMatch(
                in: output, range: NSRange(output.startIndex..., in: output)),
            let range = Range(match.range(at: 1), in: output)
        else { return nil }
        return Double(output[range])
    }
}
