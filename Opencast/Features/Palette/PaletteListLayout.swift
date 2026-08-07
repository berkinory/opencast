import SwiftUI

struct PaletteListLayout<Content: View, Target: Hashable>: View {
    let scroll: ListScrollIntent
    let scrollTarget: Target?
    let content: Content

    init(
        scroll: ListScrollIntent,
        scrollTarget: Target? = nil,
        @ViewBuilder content: () -> Content
    ) {
        self.scroll = scroll
        self.scrollTarget = scrollTarget
        self.content = content()
    }

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                content
                    .hideNativeScrollers()
                    .resetNativeScrollToTop(id: scroll.kind == .top ? scroll.id : nil)
            }
            .edgeDissolve()
            .thinScrollbar()
            .task(id: scroll) {
                guard scroll.kind == .follow, let scrollTarget else { return }
                proxy.scrollTo(scrollTarget)
            }
        }
    }
}
