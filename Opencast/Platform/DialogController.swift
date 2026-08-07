import AppKit

@MainActor
final class DialogController {
    private var isPresenting = false

    func show(
        message: String,
        informativeText: String,
        primaryTitle: String,
        secondaryTitle: String? = nil,
        style: NSAlert.Style = .informational,
        primaryIsDestructive: Bool = false
    ) -> NativeConfirmation.Response {
        guard !isPresenting else { return .secondary }
        isPresenting = true
        defer { isPresenting = false }
        return NativeConfirmation.show(
            message: message,
            informativeText: informativeText,
            primaryTitle: primaryTitle,
            secondaryTitle: secondaryTitle,
            style: style,
            primaryIsDestructive: primaryIsDestructive
        )
    }

    func confirm(
        message: String,
        informativeText: String,
        confirmTitle: String,
        style: NSAlert.Style = .warning
    ) -> Bool {
        show(
            message: message,
            informativeText: informativeText,
            primaryTitle: confirmTitle,
            secondaryTitle: "Cancel",
            style: style,
            primaryIsDestructive: style == .warning
        ) == .primary
    }
}
