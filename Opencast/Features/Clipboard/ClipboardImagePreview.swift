import AppKit
import Quartz

@MainActor
final class ClipboardImagePreview: NSObject, NSWindowDelegate {
    private var window: NSWindow?

    func show(_ url: URL) {
        window?.close()
        let frame = NSRect(x: 0, y: 0, width: 900, height: 650)
        guard let preview = QLPreviewView(frame: frame, style: .normal) else { return }
        preview.previewItem = url as NSURL
        let panel = PreviewWindow(
            contentRect: frame, styleMask: [.titled, .closable, .resizable],
            backing: .buffered, defer: false
        )
        panel.title = "Clipboard Image"
        panel.isReleasedWhenClosed = false
        panel.contentView = preview
        panel.delegate = self
        panel.center()
        window = panel
        panel.makeKeyAndOrderFront(nil)
    }

    func windowWillClose(_ notification: Notification) {
        window = nil
    }
}

private final class PreviewWindow: NSPanel {
    override func cancelOperation(_ sender: Any?) {
        close()
    }
}
