import SwiftUI

struct SnippetSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings

    var body: some View {
        SettingsPane(
            title: "Snippets",
            subtitle: "Save reusable text and expand it from short keywords.",
            systemImage: "text.quote",
            tint: Theme.Colors.systemAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Snippets",
                systemImage: "text.quote",
                tint: Theme.Colors.systemAccent,
                isEnabled: $settings.snippetsEnabled
            )

            Group {
                FeatureCommandsSettingsSection(
                    commandIDs: [.searchSnippets, .createSnippet]
                )

                SettingsSection(
                    header: "Keyword expansion",
                    subtitle: "Saved keywords expand automatically while Snippets is on.",
                    systemImage: "text.cursor",
                    tint: Theme.Colors.systemAccent
                ) {
                    SettingsControlRow(
                        title: "Expand after Space",
                        subtitle: "Wait for a space before expanding. The space is kept after the inserted text.",
                        destination: .snippetExpandAfterSpace
                    ) {
                        Toggle("Expand after Space", isOn: $settings.snippetExpandAfterSpace)
                            .settingsToggle()
                    }
                    SettingsRowDivider()
                    VStack(alignment: .leading, spacing: Theme.Spacing.md) {
                        Text("Disabled applications")
                            .font(Theme.Typography.captionSemibold)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        SettingsExcludedApplications(
                            bundleIDs: $settings.snippetDisabledApps,
                            emptyMessage: "Snippet keywords expand in every application."
                        )
                        .padding(-Theme.Settings.Layout.rowHorizontal)
                    }
                    .padding(Theme.Settings.Layout.rowHorizontal)
                    .settingsDestination(.snippetDisabledApps)
                }
            }
            .disabled(!settings.snippetsEnabled)
            .opacity(settings.snippetsEnabled ? 1 : 0.42)
        }
    }
}
