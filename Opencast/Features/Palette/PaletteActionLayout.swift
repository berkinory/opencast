import AppKit
import SwiftUI

struct PaletteActionLayout<Content: View, Footer: View>: View {
    let title: String
    let subtitle: String?
    let content: Content
    let footer: Footer

    init(
        title: String,
        subtitle: String? = nil,
        @ViewBuilder content: () -> Content,
        @ViewBuilder footer: () -> Footer
    ) {
        self.title = title
        self.subtitle = subtitle
        self.content = content()
        self.footer = footer()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: Theme.Spacing.xs) {
                Text(title)
                    .font(Theme.Typography.title3Semibold)
                    .foregroundStyle(.primary)

                if let subtitle {
                    Text(subtitle)
                        .font(Theme.Typography.callout)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, Theme.Spacing.md * 2)
            .padding(.top, Theme.Spacing.xl)
            .padding(.bottom, Theme.Spacing.lg)

            ScrollView {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, Theme.Spacing.md * 2)
                    .padding(.bottom, Theme.Spacing.xl)
            }
            .edgeDissolve()
            .thinScrollbar()

            footer
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.horizontal, Theme.Spacing.md * 2)
                .padding(.vertical, Theme.Spacing.md)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }
}

struct PaletteTextInputCursor: ViewModifier {
    func body(content: Content) -> some View {
        content.overlay(PaletteTextInputCursorView())
    }
}

private struct PaletteTextInputCursorView: NSViewRepresentable {
    func makeNSView(context: Context) -> PaletteTextInputCursorNSView {
        PaletteTextInputCursorNSView()
    }

    func updateNSView(_ nsView: PaletteTextInputCursorNSView, context: Context) {
        nsView.window?.invalidateCursorRects(for: nsView)
    }
}

private final class PaletteTextInputCursorNSView: NSView {
    private var trackingArea: NSTrackingArea?
    private var cursorIsPushed = false

    override func updateTrackingAreas() {
        if let trackingArea { removeTrackingArea(trackingArea) }
        trackingArea = NSTrackingArea(
            rect: bounds,
            options: [.activeInKeyWindow, .inVisibleRect, .mouseEnteredAndExited, .mouseMoved],
            owner: self
        )
        if let trackingArea { addTrackingArea(trackingArea) }
        super.updateTrackingAreas()
    }

    override func mouseEntered(with event: NSEvent) {
        guard !cursorIsPushed else {
            NSCursor.iBeam.set()
            return
        }
        NSCursor.iBeam.push()
        cursorIsPushed = true
    }

    override func mouseMoved(with event: NSEvent) {
        NSCursor.iBeam.set()
    }

    override func mouseExited(with event: NSEvent) {
        if cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
        NSCursor.arrow.set()
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window == nil, cursorIsPushed {
            NSCursor.pop()
            cursorIsPushed = false
        }
    }
}

extension View {
    func paletteTextInputCursor() -> some View {
        modifier(PaletteTextInputCursor())
    }
}
