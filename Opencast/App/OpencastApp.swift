import SwiftUI

@main
struct OpencastApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    // `@AppStorage` republishes only when the value changes, avoiding a scene ⇄ binding feedback loop.
    @AppStorage(SettingsKey.showInMenuBar) private var showInMenuBar = true
    @ObservedObject private var extensionScheduler = AppCore.shared.extensionScheduler

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
            if !extensionScheduler.menuBarSnapshots.isEmpty {
                Divider()
                ForEach(extensionScheduler.menuBarSnapshots) { snapshot in
                    Menu(snapshot.title) {
                        if snapshot.isStale {
                            Label("Updating…", systemImage: "clock.badge.exclamationmark")
                        }
                        if let command = extensionScheduler.command(for: snapshot) {
                            ForEach(snapshot.snapshot.items) { item in
                                Button {
                                    AppCore.shared.launcher.openExtension(command)
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text(item.title)
                                        if let subtitle = item.subtitle {
                                            Text(subtitle).foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                            if snapshot.snapshot.items.isEmpty {
                                Button("Open") { AppCore.shared.launcher.openExtension(command) }
                            }
                        }
                    }
                }
            }
            Divider()
            Button("Settings...") { AppCore.shared.showSettings() }
                .keyboardShortcut(",")
            Divider()
            Button("Quit \(appName)") { NSApp.terminate(nil) }
                .keyboardShortcut("q")
        }
    }
}
