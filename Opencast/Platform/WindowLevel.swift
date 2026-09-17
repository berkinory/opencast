import AppKit

extension NSWindow.Level {
    static let palette = NSWindow.Level(rawValue: NSWindow.Level.modalPanel.rawValue + 1)
}
