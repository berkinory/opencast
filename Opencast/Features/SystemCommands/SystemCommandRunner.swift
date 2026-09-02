import AppKit
import CoreAudio
import Darwin

struct SystemCommandFailure: LocalizedError, Sendable {
    enum Settings: Sendable, Equatable {
        case accessibility
        case automation
    }

    let message: String
    let settings: Settings?

    init(_ message: String, settings: Settings? = nil) {
        self.message = message
        self.settings = settings
    }

    var errorDescription: String? { message }
}

@MainActor
enum SystemCommandRunner {
    struct State: Sendable {
        var lastNonZeroVolume: Float32 = 0.5
    }

    private struct ProcessOutput: Sendable {
        let status: Int32
        let stdout: String
        let stderr: String
    }

    private static let volumeStep: Float32 = 1 / 16

    static func run(
        _ id: SystemCommand.ID,
        previousApp: NSRunningApplication?,
        state: State
    ) async throws -> State {
        var state = state
        switch id {
        case .sleep:
            try await runProcess("/usr/bin/pmset", arguments: ["sleepnow"])
        case .sleepDisplays:
            try await runProcess("/usr/bin/pmset", arguments: ["displaysleepnow"])
        case .restart:
            try runAppleScript("tell application \"System Events\" to restart")
        case .shutDown:
            try runAppleScript("tell application \"System Events\" to shut down")
        case .logOut:
            try runAppleScript("tell application \"System Events\" to log out")
        case .showScreenSaver:
            try openScreenSaver()
        case .playPause:
            try postMediaKey(16)
        case .nextTrack:
            try postMediaKey(17)
        case .previousTrack:
            try postMediaKey(18)
        case .toggleMute:
            try toggleMute(state: &state)
        case .volumeUp:
            try setVolume(try currentVolume() + volumeStep, state: &state)
        case .volumeDown:
            try setVolume(try currentVolume() - volumeStep, state: &state)
        case .showDesktop:
            try await runProcess(
                "/System/Applications/Mission Control.app/Contents/MacOS/Mission Control",
                arguments: ["1"])
        case .toggleAppearance:
            try runAppleScript(
                "tell application \"System Events\" to tell appearance preferences to set dark mode to not dark mode")
        case .openTrash:
            let trash = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".Trash")
            guard NSWorkspace.shared.open(trash) else {
                throw SystemCommandFailure("Finder could not open the Trash.")
            }
        case .emptyTrash:
            let items =
                try runAppleScript("tell application \"Finder\" to count items of trash")?
                .int32Value ?? 0
            if items > 0 {
                try runAppleScript("tell application \"Finder\" to empty trash")
            }
        case .ejectAllDisks:
            _ = try ejectAllDisks()
        case .toggleHiddenFiles:
            _ = try await toggleDefault(domain: "com.apple.finder", key: "AppleShowAllFiles")
            let output = try await process("/usr/bin/killall", arguments: ["Finder"])
            guard output.status == 0 || output.status == 1 else {
                let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
                throw SystemCommandFailure(
                    detail.isEmpty ? "Finder could not be restarted." : detail)
            }
        case .hideOtherApps:
            hideOtherApps(except: previousApp)
        case .unhideAllApps:
            for app in NSWorkspace.shared.runningApplications where app.isHidden {
                app.unhide()
            }
        case .quitAllApps:
            break
        }
        return state
    }

    static func caffeinate(for duration: Int? = nil) async throws {
        var arguments = ["-u"]
        if let duration { arguments += ["-t", String(duration)] }
        try await decaffeinate()
        try await startProcess("/usr/bin/caffeinate", arguments: arguments)
    }

    static func decaffeinate() async throws {
        let output = try await process("/usr/bin/killall", arguments: ["caffeinate"])
        guard output.status == 0 || output.status == 1 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemCommandFailure(
                detail.isEmpty ? "killall exited with status \(output.status)." : detail)
        }
    }

    static func isCaffeinateRunning() async -> Bool {
        guard let output = try? await process("/usr/bin/pgrep", arguments: ["-x", "caffeinate"])
        else { return false }
        return output.status == 0
    }

    private static func currentVolume() throws -> Float32 {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        var total: Float32 = 0
        for element in elements {
            var address = volumeAddress(element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr else {
                throw SystemCommandFailure("The current audio output does not support software volume.")
            }
            total += value
        }
        return total / Float32(elements.count)
    }

    private static func setVolume(_ requested: Float32, state: inout State) throws {
        let device = try defaultOutputDevice()
        let elements = try volumeElements(on: device)
        let value = min(max(requested, 0), 1)
        for element in elements {
            var address = volumeAddress(element: element)
            var settable = DarwinBoolean(false)
            guard AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                settable.boolValue
            else {
                throw SystemCommandFailure("The current audio output volume is controlled externally.")
            }
            var applied = value
            let status = AudioObjectSetPropertyData(
                device, &address, 0, nil, UInt32(MemoryLayout<Float32>.size), &applied)
            guard status == noErr else {
                throw SystemCommandFailure("macOS could not change the output volume (error \(status)).")
            }
        }
        if value > 0 {
            try? setMuted(false, on: device)
            state.lastNonZeroVolume = value
        }
    }

    private static func toggleMute(state: inout State) throws {
        let device = try defaultOutputDevice()
        var address = muteAddress
        var muted: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        if AudioObjectHasProperty(device, &address),
            AudioObjectGetPropertyData(device, &address, 0, nil, &size, &muted) == noErr
        {
            try setMuted(muted == 0, on: device)
            return
        }

        let current = try currentVolume()
        if current > 0 {
            state.lastNonZeroVolume = current
            try setVolume(0, state: &state)
        } else {
            try setVolume(state.lastNonZeroVolume, state: &state)
        }
    }

    private static func volumeElements(on device: AudioDeviceID) throws -> [AudioObjectPropertyElement] {
        var main = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &main) {
            return [kAudioObjectPropertyElementMain]
        }

        var stereoAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyPreferredChannelsForStereo,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
        var channels: (UInt32, UInt32) = (1, 2)
        var size = UInt32(MemoryLayout<(UInt32, UInt32)>.size)
        if AudioObjectGetPropertyData(device, &stereoAddress, 0, nil, &size, &channels) != noErr {
            channels = (1, 2)
        }
        let elements = [channels.0, channels.1].filter { channel in
            var address = volumeAddress(element: channel)
            return AudioObjectHasProperty(device, &address)
        }
        guard !elements.isEmpty else {
            throw SystemCommandFailure("The current audio output does not support software volume.")
        }
        return elements
    }

    private static func volumeAddress(element: AudioObjectPropertyElement)
        -> AudioObjectPropertyAddress
    {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    private static var muteAddress: AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain)
    }

    private static func defaultOutputDevice() throws -> AudioDeviceID {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        var device = AudioDeviceID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device)
        guard status == noErr, device != kAudioObjectUnknown else {
            throw SystemCommandFailure("No audio output device is available.")
        }
        return device
    }

    private static func setMuted(_ muted: Bool, on device: AudioDeviceID) throws {
        var address = muteAddress
        guard AudioObjectHasProperty(device, &address) else {
            guard muted else { return }
            throw SystemCommandFailure("The current audio output does not support mute control.")
        }
        var value: UInt32 = muted ? 1 : 0
        let status = AudioObjectSetPropertyData(
            device, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value)
        guard status == noErr else {
            throw SystemCommandFailure("macOS could not change mute state (error \(status)).")
        }
    }

    private static func postMediaKey(_ key: Int32) throws {
        guard Permissions.ensureAccessibility() else {
            throw SystemCommandFailure(
                "Allow Opencast to control your Mac in Accessibility settings, then try again.",
                settings: .accessibility)
        }
        for state in [0xA, 0xB] {
            let data1 = Int((key << 16) | (Int32(state) << 8))
            let event = NSEvent.otherEvent(
                with: .systemDefined,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                subtype: 8,
                data1: data1,
                data2: -1)
            event?.cgEvent?.post(tap: .cghidEventTap)
        }
    }

    private static func openScreenSaver() throws {
        let url = URL(fileURLWithPath: "/System/Library/CoreServices/ScreenSaverEngine.app")
        guard FileManager.default.fileExists(atPath: url.path) else {
            throw SystemCommandFailure("The macOS screen saver could not be found.")
        }
        NSWorkspace.shared.openApplication(
            at: url, configuration: NSWorkspace.OpenConfiguration())
    }

    private static func hideOtherApps(except previousApp: NSRunningApplication?) {
        let ownPID = NSRunningApplication.current.processIdentifier
        let keptPID = previousApp?.processIdentifier
        for app in NSWorkspace.shared.runningApplications
        where app.activationPolicy == .regular
            && app.processIdentifier != ownPID
            && app.processIdentifier != keptPID
        {
            app.hide()
        }
        previousApp?.unhide()
        previousApp?.activate()
    }

    @discardableResult
    private static func ejectAllDisks() throws -> Int {
        let keys: Set<URLResourceKey> = [
            .volumeIsEjectableKey, .volumeIsInternalKey, .volumeIsLocalKey,
            .volumeIsRootFileSystemKey,
        ]
        let urls =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: Array(keys), options: [.skipHiddenVolumes]) ?? []
        let ejectable = urls.filter { url in
            guard let values = try? url.resourceValues(forKeys: keys),
                values.volumeIsLocal != false,
                values.volumeIsInternal != true,
                values.volumeIsRootFileSystem != true
            else { return false }
            return values.volumeIsEjectable == true || values.volumeIsInternal == false
        }
        var failures: [String] = []
        var ejected = 0
        for url in ejectable {
            guard mountedVolumeExists(url) else { continue }
            do {
                try NSWorkspace.shared.unmountAndEjectDevice(at: url)
                ejected += 1
            } catch {
                guard !mountedVolumeExists(url) else {
                    failures.append("\(url.lastPathComponent): \(error.localizedDescription)")
                    continue
                }
                ejected += 1
            }
        }
        guard failures.isEmpty else {
            throw SystemCommandFailure(
                "Some disks could not be ejected:\n\n" + failures.joined(separator: "\n"))
        }
        return ejected
    }

    private static func mountedVolumeExists(_ url: URL) -> Bool {
        let mounted =
            FileManager.default.mountedVolumeURLs(
                includingResourceValuesForKeys: nil, options: [.skipHiddenVolumes]) ?? []
        return mounted.contains { $0.standardizedFileURL == url.standardizedFileURL }
    }

    @discardableResult
    private static func runAppleScript(_ source: String) throws -> NSAppleEventDescriptor? {
        guard let script = NSAppleScript(source: source) else {
            throw SystemCommandFailure("The system automation could not be prepared.")
        }
        var errorInfo: NSDictionary?
        let result = script.executeAndReturnError(&errorInfo)
        guard let errorInfo else { return result }
        let number = errorInfo[NSAppleScript.errorNumber] as? Int
        let detail = errorInfo[NSAppleScript.errorMessage] as? String ?? "Unknown automation error."
        if number == -1743 {
            throw SystemCommandFailure(
                "Allow Opencast to control the requested app in Automation settings, then try again.",
                settings: .automation)
        }
        throw SystemCommandFailure(detail)
    }

    @discardableResult
    private static func toggleDefault(domain: String, key: String) async throws -> Bool {
        let read = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let normalized = read.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        let current: Bool
        if read.status == 0 {
            guard let parsed = booleanDefault(normalized) else {
                throw SystemCommandFailure("macOS reported an unexpected value for this setting.")
            }
            current = parsed
        } else if read.stderr.contains("does not exist") {
            current = false
        } else {
            let detail = read.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            throw SystemCommandFailure(
                detail.isEmpty ? "macOS could not read this setting." : detail)
        }
        let requested = !current
        try await runProcess(
            "/usr/bin/defaults",
            arguments: ["write", domain, key, "-bool", requested ? "true" : "false"])
        let verify = try await process("/usr/bin/defaults", arguments: ["read", domain, key])
        let verified = verify.stdout.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard verify.status == 0, booleanDefault(verified) == requested else {
            throw SystemCommandFailure("macOS did not save the requested setting.")
        }
        return requested
    }

    private static func booleanDefault(_ value: String) -> Bool? {
        switch value {
        case "1", "true", "yes": return true
        case "0", "false", "no": return false
        default: return nil
        }
    }

    private static func runProcess(_ executable: String, arguments: [String]) async throws {
        let output = try await process(executable, arguments: arguments)
        guard output.status == 0 else {
            let detail = output.stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            let name = URL(fileURLWithPath: executable).lastPathComponent
            throw SystemCommandFailure(
                detail.isEmpty ? "\(name) exited with status \(output.status)." : detail)
        }
    }

    private static func startProcess(_ executable: String, arguments: [String]) async throws {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = FileHandle.nullDevice
            process.standardError = FileHandle.nullDevice
            do {
                try process.run()
            } catch {
                throw SystemCommandFailure(
                    "\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)"
                )
            }
        }.value
    }

    private static func process(_ executable: String, arguments: [String]) async throws -> ProcessOutput {
        try await Task.detached(priority: .userInitiated) {
            let process = Process()
            let stdout = Pipe()
            let stderr = Pipe()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.standardInput = FileHandle.nullDevice
            process.standardOutput = stdout
            process.standardError = stderr
            do {
                try process.run()
            } catch {
                throw SystemCommandFailure(
                    "\(URL(fileURLWithPath: executable).lastPathComponent) could not start: \(error.localizedDescription)"
                )
            }
            process.waitUntilExit()
            let outData = stdout.fileHandleForReading.readDataToEndOfFile()
            let errorData = stderr.fileHandleForReading.readDataToEndOfFile()
            return ProcessOutput(
                status: process.terminationStatus,
                stdout: String(data: outData, encoding: .utf8) ?? "",
                stderr: String(data: errorData, encoding: .utf8) ?? "")
        }.value
    }
}
