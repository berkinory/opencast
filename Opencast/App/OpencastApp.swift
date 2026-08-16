import SwiftUI

@main
struct OpencastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only when the value changes, avoiding a scene ⇄ binding feedback loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true

    // The display name comes from the bundle so Debug can identify itself clearly.
    private let appName = Bundle.main.appDisplayName

    var body: some Scene {
        MenuBarExtra(
            appName, systemImage: "macwindow.on.rectangle", isInserted: $showInMenuBar
        ) {
            Button("Open \(appName)") {
                AppCore.shared.showPalette(mode: .launcher, restoreAnyMode: true)
            }
            Button("Clipboard History") { AppCore.shared.showPalette(mode: .clipboard) }
            Divider()
            Button("Settings...") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit \(appName)") { NSApp.terminate(nil) }
        }
        .commands { appCommands }
    }

    @CommandsBuilder
    private var appCommands: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About \(appName)") { AppCore.shared.showAbout() }
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
        }
        CommandGroup(replacing: .appTermination) {
            Button("Close Settings") { AppCore.shared.closeSettings() }
                .keyboardShortcut("q")
        }
    }
}
