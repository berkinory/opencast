import AppKit

@MainActor
enum NativeConfirmation {
    enum Response {
        case primary
        case secondary
    }

    static func present(
        message: String,
        informativeText: String,
        confirmTitle: String
    ) -> Bool {
        show(
            message: message,
            informativeText: informativeText,
            primaryTitle: confirmTitle,
            secondaryTitle: "Cancel",
            style: .warning,
            primaryIsDestructive: true
        ) == .primary
    }

    static func show(
        message: String,
        informativeText: String,
        primaryTitle: String,
        secondaryTitle: String? = nil,
        style: NSAlert.Style = .informational,
        primaryIsDestructive: Bool = false
    ) -> Response {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.messageText = message
        alert.informativeText = informativeText
        alert.alertStyle = style

        if let secondaryTitle {
            let secondaryButton = alert.addButton(withTitle: secondaryTitle)
            secondaryButton.keyEquivalent = "\u{1b}"
        }

        let primaryButton = alert.addButton(withTitle: primaryTitle)
        primaryButton.keyEquivalent = "\r"
        primaryButton.hasDestructiveAction = primaryIsDestructive
        alert.window.level = .modalPanel

        let response = alert.runModal()
        if secondaryTitle != nil, response == .alertFirstButtonReturn {
            return .secondary
        }
        return .primary
    }
}
