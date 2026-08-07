import AppKit

@MainActor
final class SystemCommandCoordinator {
    private let appIndex: AppIndex
    private let palette: PaletteViewModel
    private let dialogs: DialogController
    private let previousApplication: () -> NSRunningApplication?
    private let hidePalette: (Bool) -> Void
    private let confirm: (String, String, String) -> Bool
    private var state = SystemCommandRunner.State()

    init(
        appIndex: AppIndex,
        palette: PaletteViewModel,
        dialogs: DialogController,
        previousApplication: @escaping () -> NSRunningApplication?,
        hidePalette: @escaping (Bool) -> Void,
        confirm: @escaping (String, String, String) -> Bool
    ) {
        self.appIndex = appIndex
        self.palette = palette
        self.dialogs = dialogs
        self.previousApplication = previousApplication
        self.hidePalette = hidePalette
        self.confirm = confirm
    }

    func quit(_ app: AppEntry) {
        guard app.kind == .application, let bundleID = app.bundleID else { return }
        let quittingPreviousApp = previousApplication()?.bundleIdentifier == bundleID
        guard AppLauncher.quit(bundleID: bundleID) else { return }
        hidePalette(!quittingPreviousApp)
    }

    func run(_ entry: AppEntry) {
        guard let command = SystemCommandCatalog.command(forEntryID: entry.id) else { return }
        let previousApp = previousApplication()
        hidePalette(false)
        Task { [weak self] in
            guard let self else { return }
            if command.id == .quitAllApps {
                quitAllApps()
                return
            }
            guard command.confirmation == .none || confirm(command) else { return }
            do {
                state = try await SystemCommandRunner.run(
                    command.id, previousApp: previousApp, state: state)
            } catch let failure as SystemCommandFailure {
                presentFailure(name: command.name, failure: failure)
            } catch {
                presentFailure(
                    name: command.name,
                    failure: SystemCommandFailure(error.localizedDescription))
            }
        }
    }

    func caffeinate(duration: Int?) {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await SystemCommandRunner.caffeinate(for: duration)
                appIndex.setCaffeinationActive(true)
                await appIndex.refresh()
                palette.postFeedback(
                    duration == nil ? "Your Mac is now caffeinated" : "Your Mac is caffeinated")
            } catch let failure as SystemCommandFailure {
                presentFailure(
                    name: duration == nil ? "Caffeinate" : "Caffeinate For", failure: failure)
            } catch {
                presentFailure(
                    name: duration == nil ? "Caffeinate" : "Caffeinate For",
                    failure: SystemCommandFailure(error.localizedDescription))
            }
        }
    }

    func decaffeinate() {
        Task { [weak self] in
            guard let self else { return }
            do {
                try await SystemCommandRunner.decaffeinate()
                appIndex.setCaffeinationActive(false)
                await appIndex.refresh()
                palette.postFeedback("Your Mac is now decaffeinated")
            } catch let failure as SystemCommandFailure {
                presentFailure(name: "Decaffeinate", failure: failure)
            } catch {
                presentFailure(
                    name: "Decaffeinate", failure: SystemCommandFailure(error.localizedDescription))
            }
        }
    }

    func duration(from values: [String]) -> Int? {
        let components = (0..<3).map { index in
            values.indices.contains(index)
                ? values[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
        }
        guard components.contains(where: { !$0.isEmpty }) else { return nil }
        let numbers = components.map { $0.isEmpty ? 0 : Int($0) }
        guard numbers.allSatisfy({ $0 != nil && $0! >= 0 }) else {
            presentFailure(
                name: "Caffeinate For",
                failure: SystemCommandFailure("Duration values must be whole numbers."))
            return nil
        }
        let (hoursSeconds, hoursOverflow) = numbers[0]!.multipliedReportingOverflow(by: 3_600)
        let (minutesSeconds, minutesOverflow) = numbers[1]!.multipliedReportingOverflow(by: 60)
        let (partial, additionOverflow) = hoursSeconds.addingReportingOverflow(minutesSeconds)
        let (totalSeconds, secondsOverflow) = partial.addingReportingOverflow(numbers[2]!)
        guard !hoursOverflow, !minutesOverflow, !additionOverflow, !secondsOverflow,
            totalSeconds > 0
        else {
            presentFailure(
                name: "Caffeinate For",
                failure: SystemCommandFailure("Duration is too large or empty."))
            return nil
        }
        return totalSeconds
    }

    private func quitAllApps() {
        let targets = AppLauncher.quitAllTargets()
        guard !targets.isEmpty,
            confirm(
                targets.count == 1 ? "Quit 1 application?" : "Quit \(targets.count) applications?",
                "Applications with unsaved changes will ask you to save.",
                "Quit All")
        else { return }
        for app in targets { app.terminate() }
    }

    private func confirm(_ command: SystemCommand) -> Bool {
        let informativeText: String
        switch command.id {
        case .restart:
            informativeText = "Open applications will be closed and your Mac will restart."
        case .shutDown:
            informativeText = "Open applications will be closed and your Mac will shut down."
        case .logOut:
            informativeText = "You will be logged out of your Mac."
        case .emptyTrash:
            informativeText = "Items in the Trash will be permanently deleted."
        case .ejectAllDisks:
            informativeText = "All ejectable local disks will be unmounted."
        default:
            informativeText = "This system action will affect your current session."
        }
        return confirm("\(command.name)?", informativeText, command.name)
    }

    private func presentFailure(name: String, failure: SystemCommandFailure) {
        let settingsTitle: String? =
            if let settings = failure.settings {
                settings == .accessibility
                    ? "Open Accessibility Settings…" : "Open Automation Settings…"
            } else {
                nil
            }
        let response = dialogs.show(
            message: "“\(name)” Failed",
            informativeText: failure.message,
            primaryTitle: "OK",
            secondaryTitle: settingsTitle,
            style: .critical
        )
        guard response == .secondary, let settings = failure.settings else { return }
        switch settings {
        case .accessibility:
            Permissions.openAccessibilitySettings()
        case .automation:
            if let url = URL(
                string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation")
            {
                NSWorkspace.shared.open(url)
            }
        }
    }
}
