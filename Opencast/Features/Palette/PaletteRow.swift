import SwiftUI

struct PaletteRow<Leading: View, Content: View, Trailing: View>: View {
    let selected: Bool
    let leading: Leading
    let content: Content
    let trailing: Trailing
    @State private var hovered = false

    init(
        selected: Bool,
        @ViewBuilder leading: () -> Leading,
        @ViewBuilder content: () -> Content,
        @ViewBuilder trailing: () -> Trailing
    ) {
        self.selected = selected
        self.leading = leading()
        self.content = content()
        self.trailing = trailing()
    }

    var body: some View {
        HStack(spacing: Theme.Spacing.lg) {
            leading
                .frame(width: Theme.Size.rowIcon, height: Theme.Size.rowIcon)
            content
            Spacer(minLength: 0)
            trailing
        }
        .padding(.horizontal, Theme.Spacing.md)
        .padding(.vertical, Theme.Spacing.rowVertical)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
    }

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }
}
