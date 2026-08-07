import AppKit

enum AppLauncher {

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

    /// Asks every running instance of a bundle ID to quit — graceful, so an app with unsaved work still gets to put its own sheet up. False when nothing was running.
    @MainActor
    @discardableResult
    static func quit(bundleID: String) -> Bool {
        let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID)
        for app in running { app.terminate() }
        return !running.isEmpty
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
