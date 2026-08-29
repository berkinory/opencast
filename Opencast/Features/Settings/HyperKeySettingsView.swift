import SwiftUI

struct HyperKeySettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var hyperKey = AppCore.shared.hyperKey

    var body: some View {
        SettingsPane(
            title: "Hyper Key",
            subtitle: "Turn one physical key into a fast modifier for your shortcuts.",
            systemImage: "capslock",
            tint: Theme.Colors.systemAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Hyper Key",
                systemImage: "capslock",
                tint: Theme.Colors.systemAccent,
                isEnabled: $settings.hyperKeyEnabled
            )

            Group {
                SettingsSection(
                    header: "Key",
                    subtitle: "Hold this key together with any shortcut key.",
                    systemImage: "keyboard",
                    tint: Theme.Colors.systemAccent
                ) {
                    SettingsControlRow(
                        title: "Hyper key",
                        subtitle: "The selected key becomes ⌃⌥⇧⌘ while held."
                    ) {
                        Picker("Hyper key", selection: $settings.hyperKey) {
                            ForEach(HyperKey.allCases) { key in
                                Text(key.title).tag(key)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }

                    SettingsRowDivider()

                    SettingsControlRow(
                        title: "Tap behavior",
                        subtitle: settings.hyperTapBehavior.subtitle
                    ) {
                        Picker("Tap behavior", selection: $settings.hyperTapBehavior) {
                            ForEach(HyperTapBehavior.allCases) { behavior in
                                Text(behavior.title).tag(behavior)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                if hyperKey.needsAccessibility {
                    SettingsStatusCard(
                        title: "Accessibility access required",
                        message: "Allow Opencast in System Settings so it can transform the selected key.",
                        systemImage: "exclamationmark.triangle",
                        tint: Theme.Colors.warning
                    ) {
                        Button("Open Settings…") {
                            Permissions.ensureAccessibility()
                            Permissions.openAccessibilitySettings()
                        }
                        .controlSize(.small)
                    }
                } else if hyperKey.isActive {
                    SettingsStatusCard(
                        title: "Hyper Key is active",
                        message: "Try \(settings.hyperKey.symbol) + a key in any shortcut recorder.",
                        systemImage: "checkmark.circle",
                        tint: Theme.Colors.success
                    )
                }
            }
            .disabled(!settings.hyperKeyEnabled)
            .opacity(settings.hyperKeyEnabled ? 1 : 0.42)
        }
    }
}
