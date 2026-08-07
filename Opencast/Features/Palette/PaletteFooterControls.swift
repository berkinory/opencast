import SwiftUI

struct PaletteBarButton<Label: View>: View {
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovered = false

    var body: some View {
        Button(action: action) {
            label
                .padding(.horizontal, Theme.Spacing.md)
                .frame(height: 28)
                .contentShape(Capsule())
                .background(Capsule().fill(hovered ? Theme.Colors.rowHover : Color.clear))
        }
        .buttonStyle(.plain)
        .onHover { hovered = $0 }
    }
}

struct PaletteFeedbackButton: View {
    let message: String
    let tone: PaletteFeedback.Tone

    private var accent: Color {
        switch tone {
        case .success: Theme.Colors.feedbackAccent
        case .warning: Theme.Colors.warning
        case .error: Theme.Colors.destructive
        }
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.md) {
            ZStack {
                Circle()
                    .fill(
                        RadialGradient(
                            colors: [
                                accent.opacity(0.34),
                                accent.opacity(0.12),
                                .clear,
                            ],
                            center: .center,
                            startRadius: 0,
                            endRadius: Theme.Size.feedbackHalo / 2
                        )
                    )
                Circle()
                    .fill(accent)
                    .frame(width: Theme.Spacing.sm, height: Theme.Spacing.sm)
            }
            .frame(width: Theme.Size.feedbackHalo, height: Theme.Size.feedbackHalo)
            Text(message)
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textPrimary)
                .lineLimit(1)
        }
        .padding(.leading, Theme.Spacing.xl)
        .padding(.trailing, Theme.Spacing.xxl)
        .frame(height: Theme.Size.menuButton)
        .background {
            Capsule()
                .fill(Theme.Colors.feedbackShade)
                .overlay {
                    Capsule().fill(accent.opacity(0.18))
                }
                .overlay {
                    Capsule().strokeBorder(Theme.Colors.feedbackStroke, lineWidth: 1)
                }
        }
        .allowsHitTesting(false)
    }
}

struct PaletteContextPill: View {
    let title: String
    let systemImage: String
    var tint: Color = Theme.Colors.textSecondary

    var body: some View {
        HStack(spacing: Theme.Spacing.sm) {
            FeatureIcon(systemImage: systemImage, tint: tint, size: Theme.Size.rowIcon)
            Text(title)
                .font(Theme.Typography.bar)
                .foregroundStyle(Theme.Colors.textSecondary)
                .lineLimit(1)
        }
        .padding(.horizontal, Theme.Spacing.md)
        .frame(height: Theme.Size.menuButton)
        .paletteFooterSurface(in: Capsule())
    }
}

struct PaletteActionGroup: View {
    let primaryTitle: String
    let primaryShortcut: [String]
    let primaryAction: () -> Void
    var primaryColor: Color = Theme.Colors.textPrimary
    var secondaryTitle: String?
    var secondaryShortcut: [String] = []
    var secondaryAction: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            PaletteBarButton(action: primaryAction) {
                HStack(spacing: Theme.Spacing.sm) {
                    Text(primaryTitle)
                        .font(Theme.Typography.bar)
                        .foregroundStyle(primaryColor)
                    shortcut(primaryShortcut)
                }
            }
            if let secondaryTitle, let secondaryAction {
                PaletteBarButton(action: secondaryAction) {
                    HStack(spacing: Theme.Spacing.sm) {
                        Text(secondaryTitle)
                            .font(Theme.Typography.bar)
                            .foregroundStyle(Theme.Colors.textSecondary)
                        shortcut(secondaryShortcut)
                    }
                }
            }
        }
        .padding(Theme.Spacing.xs)
        .paletteFooterSurface(in: Capsule())
    }

    @ViewBuilder
    private func shortcut(_ keys: [String]) -> some View {
        HStack(spacing: Theme.Spacing.xxs) {
            ForEach(Array(keys.enumerated()), id: \.offset) { _, key in
                KeyCapChip(text: key, style: .filled)
            }
        }
    }
}

extension View {
    func paletteFooterSurface<S: Shape>(in shape: S) -> some View {
        background(shape.fill(Theme.Colors.footerSurface))
            .overlay {
                shape.stroke(Theme.Colors.footerStroke, lineWidth: 1)
            }
    }
}
