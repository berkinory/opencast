import AppKit
import SwiftUI

extension View {
    func overlayScroller(disablesElasticity: Bool = false) -> some View {
        background(
            OverlayScrollerConfigurator(disablesElasticity: disablesElasticity)
                .frame(width: 0, height: 0)
        )
    }
}

private struct OverlayScrollerConfigurator: NSViewRepresentable {
    let disablesElasticity: Bool

    func makeNSView(context: Context) -> NSView {
        ProbeView(disablesElasticity: disablesElasticity)
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let probe = nsView as? ProbeView else { return }
        probe.disablesElasticity = disablesElasticity
        probe.applyOverlayStyle()
    }

    private final class ProbeView: NSView {
        var disablesElasticity: Bool
        private var attemptsRemaining = 12
        private var styleObserver: NotificationToken?

        init(disablesElasticity: Bool) {
            self.disablesElasticity = disablesElasticity
            super.init(frame: .zero)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) { fatalError() }

        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard window != nil else {
                styleObserver = nil
                return
            }
            observeStyleChanges()
            attemptsRemaining = 12  // re-attached to a fresh hierarchy; give the splice a few ticks again
            applyOverlayStyle()
        }

        /// AppKit resets scroller style back to the system preference on this notification, so re-apply on the next tick after its own handler runs.
        private func observeStyleChanges() {
            guard styleObserver == nil else { return }
            let token = NotificationCenter.default.addObserver(
                forName: NSScroller.preferredScrollerStyleDidChangeNotification,
                object: nil, queue: .main
            ) { [weak self] _ in
                DispatchQueue.main.async { self?.applyOverlayStyle() }
            }
            styleObserver = NotificationToken(token, center: .default)
        }

        func applyOverlayStyle() {
            guard let scrollView = enclosingScrollView else {
                // Not spliced into the scroll view yet; retry next tick, bounded so a view that never lands in one can't spin the main thread.
                guard attemptsRemaining > 0 else { return }
                attemptsRemaining -= 1
                DispatchQueue.main.async { [weak self] in self?.applyOverlayStyle() }
                return
            }
            if disablesElasticity {
                scrollView.verticalScrollElasticity = .none
                scrollView.horizontalScrollElasticity = .none
            }
            guard scrollView.scrollerStyle != .overlay || !scrollView.autohidesScrollers else {
                return  // already in the target state — don't churn layout on re-runs
            }
            scrollView.scrollerStyle = .overlay  // thin floating knob that reserves no width
            scrollView.autohidesScrollers = true
            scrollView.hasVerticalScroller = true
            scrollView.tile()  // reclaim any gutter the legacy scroller had reserved, same layout pass
        }
    }
}
