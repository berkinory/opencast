import AppKit
import Carbon.HIToolbox
import SwiftUI

/// Borderless floating panel that hosts the SwiftUI command palette.
final class PalettePanel: NSPanel {
    /// Called for a bare backspace before it reaches the field editor (return true to consume); the field editor swallows plain backspace itself, so SwiftUI `onKeyPress` up the hierarchy never sees it.
    var onBareBackspace: (() -> Bool)?
    var onBareSpace: (() -> Bool)?
    var onEscape: (() -> Bool)?
    var onCommandShortcut: ((NSEvent) -> Bool)?
    /// Arms the hover highlight from `sendEvent` — the one place both event streams pass through, so a keyboard-driven scroll under a still pointer never fires `.mouseMoved` and hover stays disarmed. Also carries the caret-hide hook fired when a footer menu opens.
    weak var paletteViewModel: PaletteViewModel? {
        didSet {
            paletteViewModel?.onMenuOpenChanged = { [weak self] open in self?.setSearchCaretHidden(open) }
        }
    }

    /// Keys that drive an open menu (navigate/activate/dismiss); they must reach SwiftUI's `onKeyPress` even while the menu freezes text editing.
    private static let menuNavKeys: Set<Int> = [
        kVK_UpArrow, kVK_DownArrow, kVK_LeftArrow, kVK_RightArrow,
        kVK_Return, kVK_ANSI_KeypadEnter, kVK_Escape, kVK_Tab,
    ]

    private static let cursorEvents: Set<NSEvent.EventType> = [
        .mouseMoved, .mouseEntered, .mouseExited, .cursorUpdate,
        .leftMouseDown, .leftMouseUp, .leftMouseDragged,
    ]

    private static let fieldEditorSlack: CGFloat = 2

    private var searchFieldRect: CGRect {
        guard let frame = paletteViewModel?.searchFieldFrame,
            !frame.isEmpty,
            let height = contentView?.bounds.height
        else { return .zero }
        return CGRect(
            x: frame.minX,
            y: height - frame.maxY,
            width: frame.width,
            height: frame.height
        )
    }

    private func applyCursorPolicy(for event: NSEvent) {
        guard Self.cursorEvents.contains(event.type) else { return }
        let field = searchFieldRect.insetBy(dx: -Self.fieldEditorSlack, dy: -Self.fieldEditorSlack)
        let point = convertPoint(fromScreen: NSEvent.mouseLocation)
        let cursor: NSCursor = field.contains(point) ? .iBeam : .arrow
        guard NSCursor.current !== cursor else { return }
        cursor.set()
    }

    /// Hide/show the caret on SwiftUI's *own* live field editor (the current first responder) without replacing it — SwiftUI force-casts the field editor to a private subclass, so vending our own crashes; we can only tune the existing one. The field never resigns first responder, so its text/placeholder never reflows.
    private func setSearchCaretHidden(_ hidden: Bool) {
        guard let editor = firstResponder as? NSTextView else { return }
        editor.insertionPointColor = hidden ? .clear : NSColor.textColor
        // Force an immediate redraw so the caret vanishes/returns on the menu toggle instead of waiting out the blink timer.
        editor.updateInsertionPointStateAndRestartTimer(!hidden)
    }

    override func sendEvent(_ event: NSEvent) {
        defer { applyCursorPolicy(for: event) }
        switch event.type {
        case .mouseMoved: paletteViewModel?.hoverHighlightArmed = true
        case .keyDown: paletteViewModel?.hoverHighlightArmed = false
        default: break
        }
        if event.type == .keyDown,
            event.modifierFlags.contains(.control),
            event.modifierFlags.intersection([.command, .option, .shift]).isEmpty,
            let arrow = Self.arrowAlias(for: event.charactersIgnoringModifiers),
            let rewritten = arrowKeyDown(arrow, from: event)
        {
            super.sendEvent(rewritten)
            return
        }
        if event.type == .keyDown,
            let navigation = Self.modifiedVerticalNavigation(for: event),
            paletteViewModel?.onRowNavigation?(navigation) == true
        {
            return
        }
        if event.type == .keyDown,
            event.modifierFlags.contains(.command),
            onCommandShortcut?(event) == true
        {
            return
        }
        // A footer menu owns the keyboard: the search field stays first responder (no focus swap, so nothing reflows) with only its caret hidden; swallow text-editing keystrokes before the field editor consumes them, but let shortcut chords (⌘K, ⌘⌫) and menu-nav keys reach SwiftUI's onKeyPress.
        if event.type == .keyDown,
            paletteViewModel?.menuOpen == true,
            event.modifierFlags.intersection([.command, .control]).isEmpty,
            !Self.menuNavKeys.contains(Int(event.keyCode))
        {
            return
        }
        if event.type == .keyDown,
            let delta = Self.verticalArrowDelta(for: event.keyCode),
            paletteViewModel?.onInlineArgumentsVerticalArrow?(delta) == true
        {
            return
        }
        if event.type == .keyDown,
            event.keyCode == kVK_Escape,
            paletteViewModel?.onInlineArgumentsEscape?() == true
        {
            return
        }
        if event.type == .keyDown,
            event.keyCode == kVK_Escape,
            onEscape?() == true
        {
            return
        }
        if event.type == .keyDown,
            event.keyCode == kVK_Tab,
            paletteViewModel?.onInlineArgumentsTab?() == true
        {
            return
        }
        if event.type == .keyDown,
            event.keyCode == kVK_Tab,
            firstResponder is NSTextField || firstResponder is NSTextView
        {
            return
        }
        if event.type == .keyDown,
            event.keyCode == kVK_Return || event.keyCode == kVK_ANSI_KeypadEnter,
            event.modifierFlags.intersection([.command, .option, .control, .shift]) == .command,
            paletteViewModel?.onCommandEnter?() == true
        {
            return
        }
        if event.type == .keyDown,
            event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty,
            paletteViewModel?.menuOpen != true
        {
            if Int(event.keyCode) == kVK_Delete, onBareBackspace?() == true { return }
            if Int(event.keyCode) == kVK_Space, onBareSpace?() == true { return }
        }
        super.sendEvent(event)
    }

    private static func verticalArrowDelta(for keyCode: UInt16) -> Int? {
        switch Int(keyCode) {
        case kVK_UpArrow: return -1
        case kVK_DownArrow: return 1
        default: return nil
        }
    }

    private static func modifiedVerticalNavigation(for event: NSEvent) -> PaletteRowNavigation? {
        let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        switch (Int(event.keyCode), modifiers) {
        case (kVK_UpArrow, .option): return .offset(-5)
        case (kVK_DownArrow, .option): return .offset(5)
        case (kVK_UpArrow, .command): return .edge(-1)
        case (kVK_DownArrow, .command): return .edge(1)
        default: return nil
        }
    }

    private static func arrowAlias(for characters: String?) -> (keyCode: Int, character: Int)? {
        switch characters {
        case "n": (kVK_DownArrow, NSDownArrowFunctionKey)
        case "p": (kVK_UpArrow, NSUpArrowFunctionKey)
        case "f": (kVK_RightArrow, NSRightArrowFunctionKey)
        case "b": (kVK_LeftArrow, NSLeftArrowFunctionKey)
        default: nil
        }
    }

    private func arrowKeyDown(
        _ arrow: (keyCode: Int, character: Int), from event: NSEvent
    ) -> NSEvent? {
        guard let scalar = UnicodeScalar(UInt32(arrow.character)) else { return nil }
        let character = String(scalar)
        return NSEvent.keyEvent(
            with: .keyDown,
            location: event.locationInWindow,
            modifierFlags: [.function, .numericPad],
            timestamp: event.timestamp,
            windowNumber: event.windowNumber,
            context: nil,
            characters: character,
            charactersIgnoringModifiers: character,
            isARepeat: event.isARepeat,
            keyCode: UInt16(arrow.keyCode))
    }

    init<Content: View>(rootView: Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 750, height: 475),
            styleMask: [.borderless, .fullSizeContentView, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        acceptsMouseMovedEvents = true
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isMovableByWindowBackground = false
        titleVisibility = .hidden
        titlebarAppearsTransparent = true
        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        animationBehavior = .none
        isReleasedWhenClosed = false

        let hosting = PaletteHostingView(rootView: rootView)
        hosting.wantsLayer = true
        // The controller owns the frame: without this the hosting view resizes the panel to fit the SwiftUI content, dropping the top edge on the first compact→expanded mount.
        hosting.sizingOptions = []
        contentView = hosting
    }

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

private final class PaletteHostingView<Content: View>: NSHostingView<Content> {
    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .arrow)
        super.resetCursorRects()
    }
}
