import AppKit
import SwiftUI

@MainActor
final class ToastWindowController {
    private var panel: NSPanel?
    private var hosting: NSHostingView<FeedbackToastView>?
    private var dismissTask: Task<Void, Never>?
    private var fadeTask: Task<Void, Never>?
    private var currentID: String?

    func show(
        id: String? = nil,
        title: String? = nil,
        message: String,
        tone: FeedbackToastTone = .success
    ) {
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty else { return }

        dismissTask?.cancel()
        fadeTask?.cancel()
        let toastID = id ?? UUID().uuidString
        currentID = toastID
        let panel = ensurePanel()
        hosting?.rootView = FeedbackToastView(title: title, message: message, tone: tone)
        hosting?.layoutSubtreeIfNeeded()
        let size = toastSize()
        position(panel, size: size)

        if panel.isVisible {
            panel.alphaValue = 1
        } else {
            panel.alphaValue = 0
            panel.orderFrontRegardless()
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.16
                panel.animator().alphaValue = 1
            }
        }
        scheduleDismiss(for: toastID)
    }

    func hide(id: String? = nil) {
        guard id == nil || id == currentID else { return }
        dismissTask?.cancel()
        dismissTask = nil
        fadeTask?.cancel()
        currentID = nil
        guard let panel, panel.isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.16
            panel.animator().alphaValue = 0
        }
        fadeTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(160))
            guard !Task.isCancelled else { return }
            self?.panel?.orderOut(nil)
            self?.panel?.alphaValue = 1
        }
    }

    private func ensurePanel() -> NSPanel {
        if let panel { return panel }
        let panel = NSPanel(
            contentRect: .zero,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.animationBehavior = .utilityWindow
        panel.isReleasedWhenClosed = false
        let hosting = NSHostingView(
            rootView: FeedbackToastView(title: nil, message: "", tone: .success)
        )
        hosting.sizingOptions = [.intrinsicContentSize]
        panel.contentView = hosting
        self.panel = panel
        self.hosting = hosting
        return panel
    }

    private func toastSize() -> CGSize {
        guard let hosting else {
            return CGSize(width: Theme.Size.menuButton, height: 0)
        }
        let fitting = hosting.fittingSize
        return CGSize(
            width: min(max(fitting.width, Theme.Size.menuButton), Theme.Size.feedbackToastMaxWidth),
            height: max(fitting.height, Theme.Size.menuButton)
        )
    }

    private func position(_ panel: NSPanel, size: CGSize) {
        guard let screen = targetScreen() else { return }
        let visible = screen.visibleFrame
        panel.setFrame(
            NSRect(
                x: visible.midX - size.width / 2,
                y: visible.minY + Theme.Size.feedbackToastBottomInset,
                width: size.width,
                height: size.height
            ),
            display: true
        )
    }

    private func targetScreen() -> NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func scheduleDismiss(for id: String) {
        dismissTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(2.4))
            guard !Task.isCancelled else { return }
            self?.hide(id: id)
        }
    }
}
