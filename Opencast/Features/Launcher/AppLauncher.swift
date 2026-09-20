import AppKit

enum AppLauncher {

    @MainActor
    static func running(at url: URL) -> [NSRunningApplication] {
        let path = ApplicationIdentity.path(url)
        return NSWorkspace.shared.runningApplications.filter {
            $0.bundleURL.map(ApplicationIdentity.path) == path
        }
    }

    @MainActor
    static func toggle(url: URL) {
        if let active = running(at: url).first(where: \.isActive) {
            active.hide()
        } else if FileManager.default.fileExists(atPath: url.path) {
            Task { try? await launch(url) }
        }
    }

    enum RestartError: LocalizedError {
        case notRunning
        case didNotTerminate

        var errorDescription: String? {
            switch self {
            case .notRunning: return "The application is not running."
            case .didNotTerminate: return "The application did not close in time."
            }
        }
    }

    @MainActor
    static func launch(_ url: URL) async throws {
        let workspace = NSWorkspace.shared
        let focusGuard = LaunchFocusGuard(workspace: workspace)
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        let application = try await workspace.openApplication(at: url, configuration: configuration)

        guard (try? await Task.sleep(for: .milliseconds(500))) != nil,
            focusGuard.shouldRetryActivation(of: application, workspace: workspace)
        else { return }

        application.unhide()
        application.activate()
    }

    @MainActor
    static func showInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    @MainActor
    static func open(_ quicklink: Quicklink) -> Bool {
        let rawLink = NSString(string: quicklink.link).expandingTildeInPath
        let target =
            URL(string: rawLink).flatMap { $0.scheme == nil ? nil : $0 }
            ?? URL(fileURLWithPath: rawLink)
        guard
            let applicationURL = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: quicklink.openWithBundleID
            )
        else { return false }
        NSWorkspace.shared.open(
            [target],
            withApplicationAt: applicationURL,
            configuration: NSWorkspace.OpenConfiguration(),
            completionHandler: nil
        )
        return true
    }

    /// Opens System Settings at the pane backed by the given extension bundle ID.
    @MainActor
    static func openSettingsPane(bundleID: String) {
        guard let url = URL(string: "x-apple.systempreferences:" + bundleID) else { return }
        NSWorkspace.shared.open(url)
    }

    /// Focus the app if it isn't frontmost, hide it if it is, launch it if it isn't running.
    @MainActor
    static func toggle(bundleID: String) {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
            .first
        if let running, running.isActive {
            running.hide()
            return
        }
        if let url = running?.bundleURL
            ?? NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
        {
            // Preserve Dock-click semantics while guarding the rare launch that misses its foreground handoff.
            Task { try? await launch(url) }
        } else if let running {
            // Running app whose bundle URL can't be resolved (moved or deleted since launch).
            running.unhide()
            running.activate()
        }
    }

    @MainActor
    static func restart(url: URL) async throws {
        let running = running(at: url)
        guard !running.isEmpty else { throw RestartError.notRunning }

        let processIDs = Set(running.map({ $0.processIdentifier }))
        for app in running { app.terminate() }

        let deadline = Date().addingTimeInterval(5)
        while true {
            let remaining = Self.running(at: url)
                .contains { processIDs.contains($0.processIdentifier) }
            if !remaining { break }
            guard Date() < deadline else { throw RestartError.didNotTerminate }
            try await Task.sleep(for: .milliseconds(50))
        }

        try await launch(url)
    }

    @MainActor
    @discardableResult
    static func quit(url: URL) -> Bool {
        let running = running(at: url)
        for app in running { app.terminate() }
        return !running.isEmpty
    }

    @MainActor
    @discardableResult
    static func forceQuit(url: URL) -> Bool {
        let running = running(at: url)
        var terminated = false
        for app in running { terminated = app.forceTerminate() || terminated }
        return terminated
    }

    /// Finder is never a Quit All target: `terminate()` only makes it relaunch, and nobody means the desktop when they say "quit everything".
    private static let quitAllExclusions: Set<String> = ["com.apple.finder"]

    /// What Quit All acts on: every app with a Dock presence, minus Finder and Opencast itself. Accessories and background agents are left alone. The caller resolves this once and terminates that same list, so the set it confirms is the set it quits.
    @MainActor
    static func quitAllTargets() -> [NSRunningApplication] {
        // Excluded by PID, not by activation policy: About/Settings temporarily flips Opencast to `.regular`, which a policy-only filter would read as a target.
        let ownPID = NSRunningApplication.current.processIdentifier
        return NSWorkspace.shared.runningApplications.filter { app in
            app.activationPolicy == .regular
                && app.processIdentifier != ownPID
                && !quitAllExclusions.contains(app.bundleIdentifier ?? "")
        }
    }
}

@MainActor
private final class LaunchFocusGuard {
    private let initialFrontmostPID: pid_t?
    private var observedDifferentActivation = false
    private var activationToken: NotificationToken?

    init(workspace: NSWorkspace) {
        initialFrontmostPID = workspace.frontmostApplication?.processIdentifier
        let center = workspace.notificationCenter
        let token = center.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard
                let application = notification.userInfo?[NSWorkspace.applicationUserInfoKey]
                    as? NSRunningApplication
            else { return }
            let activatedPID = application.processIdentifier
            MainActor.assumeIsolated {
                guard let self, activatedPID != self.initialFrontmostPID else { return }
                self.observedDifferentActivation = true
            }
        }
        activationToken = NotificationToken(token, center: center)
    }

    func shouldRetryActivation(
        of application: NSRunningApplication,
        workspace: NSWorkspace
    ) -> Bool {
        !observedDifferentActivation
            && !application.isActive
            && !application.isTerminated
            && workspace.frontmostApplication?.processIdentifier == initialFrontmostPID
    }
}
