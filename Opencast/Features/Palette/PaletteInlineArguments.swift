import SwiftUI

struct PaletteInlineArguments: View {
    let arguments: [InlineArgument]
    @Binding var values: [String]
    let focusRequest: Int?
    let onFocusChanged: (Int?) -> Void
    let onSubmit: () -> Void

    @FocusState private var focusedArgument: Int?

    var body: some View {
        HStack(spacing: Theme.Spacing.xs) {
            ForEach(Array(arguments.enumerated()), id: \.element.id) { index, argument in
                PaletteInlineArgumentField(
                    argument: argument,
                    text: Binding(
                        get: { values.indices.contains(index) ? values[index] : "" },
                        set: { newValue in
                            while values.count <= index { values.append("") }
                            values[index] = newValue
                        }
                    ),
                    focused: $focusedArgument,
                    index: index,
                    onSubmit: onSubmit
                )
            }
        }
        .onChange(of: focusRequest) { _, request in
            focusedArgument = request
        }
        .onChange(of: focusedArgument) { _, focus in
            onFocusChanged(focus)
        }
        .onAppear {
            focusedArgument = focusRequest
        }
    }
}

private struct PaletteInlineArgumentField: View {
    let argument: InlineArgument
    @Binding var text: String
    let focused: FocusState<Int?>.Binding
    let index: Int
    let onSubmit: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            TextField(
                "", text: $text,
                prompt: Text(argument.placeholder)
                    .font(Theme.Typography.callout)
                    .foregroundStyle(Theme.Colors.textSecondary)
            )
            .textFieldStyle(.plain)
            .font(Theme.Typography.callout)
            .foregroundStyle(Theme.Colors.textPrimary)
            .tint(Theme.Colors.textPrimary)
            .focused(focused, equals: index)
            .paletteTextInputCursor()
            .onSubmit(onSubmit)
            .padding(.horizontal, Theme.Spacing.sm)
            .frame(minWidth: Theme.Size.inlineArgumentMinimumWidth)
            .frame(height: Theme.Size.inlineArgumentHeight)
            .fixedSize(horizontal: true, vertical: false)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .fill(Theme.Colors.controlSurface)
            )
            .overlay {
                RoundedRectangle(cornerRadius: Theme.Radius.row, style: .continuous)
                    .stroke(
                        focused.wrappedValue == index
                            ? Theme.Colors.border
                            : Color.clear,
                        lineWidth: 1
                    )
            }
            .help(argument.help)

            Image(systemName: "questionmark")
                .font(Theme.Typography.iconMicro)
                .foregroundStyle(Theme.Colors.textOnPrimary)
                .frame(width: Theme.Size.inlineArgumentHelpBadge, height: Theme.Size.inlineArgumentHelpBadge)
                .background(Circle().fill(Theme.Colors.textSecondary))
                .offset(x: 6, y: -7)
        }
    }
}
