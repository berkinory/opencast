import SwiftUI

struct ClipboardSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Clipboard",
            subtitle: "Decide how long history stays and which apps remain private.",
            systemImage: "clipboard",
            tint: Theme.Colors.clipboardAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Clipboard history",
                systemImage: "clipboard",
                tint: Theme.Colors.clipboardAccent,
                isEnabled: $settings.clipboardEnabled
            )

            Group {
                FeatureCommandsSettingsSection(
                    commandIDs: [.clipboardHistory],
                    tint: Theme.Colors.clipboardAccent
                )

                SettingsSection(
                    header: "History",
                    subtitle: "Older entries are removed automatically.",
                    systemImage: "clock.arrow.circlepath",
                    tint: Theme.Colors.clipboardAccent
                ) {
                    SettingsControlRow(
                        title: "Keep history for",
                        subtitle: "Text and images follow the same retention period.",
                        destination: .clipboardRetention
                    ) {
                        Picker("Keep history for", selection: $settings.clipboardRetention) {
                            ForEach(ClipboardRetention.allCases) { retention in
                                Text(retention.title).tag(retention)
                            }
                        }
                        .labelsHidden()
                        .fixedSize()
                        .onChange(of: settings.clipboardRetention) {
                            let store = AppCore.shared.clipboardStore
                            store.maxAge = settings.clipboardRetention.maxAge
                            store.enforceLimits()
                        }
                    }
                }

                SettingsSection(
                    header: "Private applications",
                    subtitle: "Clipboard changes from these apps are never recorded.",
                    systemImage: "eye.slash",
                    tint: Theme.Colors.systemAccent,
                    destination: .clipboardExcludedApps
                ) {
                    SettingsExcludedApplications(
                        bundleIDs: $settings.clipboardDisabledApps,
                        emptyMessage: "Clipboard changes from every app are recorded."
                    )
                }

                SettingsStatusCard(
                    title: "Clear clipboard history",
                    message: "Remove unpinned clips and images. Pinned entries are kept.",
                    systemImage: "trash",
                    tint: Theme.Colors.destructive
                ) {
                    Button("Clear", role: .destructive) {
                        if !AppCore.shared.clipboardStore.clearHistory() { NSSound.beep() }
                    }
                    .controlSize(.small)
                }
                .settingsDestination(.clipboardClearHistory)
            }
            .disabled(!settings.clipboardEnabled)
            .opacity(settings.clipboardEnabled ? 1 : 0.42)
        }
    }
}
