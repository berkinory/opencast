import SwiftUI

struct PaletteGridSection<Item> {
    let id: String
    let title: String?
    let items: [Item]
}

private struct PaletteGridRowModel<Item> {
    let id: String
    let start: Int
    let items: [Item]
}

struct PaletteGridLayout<Item, Cell: View, Footer: View>: View {
    let sections: [PaletteGridSection<Item>]
    let columns: Int
    let selection: Int
    let scroll: ListScrollIntent
    let columnSpacing: CGFloat
    let rowSpacing: CGFloat
    let minimumCellHeight: CGFloat
    let contentInsets: EdgeInsets
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    @ViewBuilder let cell: (Item, Bool, Bool) -> Cell
    @ViewBuilder let footer: () -> Footer

    private enum RenderItem {
        case header(id: String, title: String)
        case row(PaletteGridRowModel<Item>)

        var id: String {
            switch self {
            case .header(let id, _): return id
            case .row(let row): return row.id
            }
        }
    }

    private var renderItems: [RenderItem] {
        var result: [RenderItem] = []
        var start = 0
        for section in sections where !section.items.isEmpty {
            if let title = section.title {
                result.append(.header(id: section.id + "-header", title: title))
            }
            var offset = 0
            var row = 0
            while offset < section.items.count {
                let end = min(offset + columns, section.items.count)
                result.append(
                    .row(
                        PaletteGridRowModel(
                            id: section.id + "-row-\(row)",
                            start: start + offset,
                            items: Array(section.items[offset..<end])
                        )))
                offset = end
                row += 1
            }
            start += section.items.count
        }
        return result
    }

    private var selectedRowID: String? {
        var start = 0
        for section in sections where !section.items.isEmpty {
            let local = selection - start
            if section.items.indices.contains(local) {
                return section.id + "-row-\(local / columns)"
            }
            start += section.items.count
        }
        return nil
    }

    var body: some View {
        let renderItems = renderItems
        let firstItemID = renderItems.first?.id
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(renderItems, id: \.id) { item in
                        switch item {
                        case .header(_, let title):
                            SectionHeader(title: title, isFirst: item.id == firstItemID)
                        case .row(let row):
                            PaletteGridRow(
                                row: row,
                                columns: columns,
                                selection: selection,
                                columnSpacing: columnSpacing,
                                minimumCellHeight: minimumCellHeight,
                                onSelect: onSelect,
                                onActivate: onActivate,
                                onActions: onActions,
                                cell: cell
                            )
                            .padding(.bottom, rowSpacing)
                        }
                    }
                    footer()
                }
                .padding(contentInsets)
                .hideNativeScrollers()
                .resetNativeScrollToTop(id: scroll.kind == .top ? scroll.id : nil)
            }
            .edgeDissolve()
            .thinScrollbar()
            .modifier(
                GridSelectionFollowing(
                    scroll: scroll,
                    selectedRowID: selectedRowID,
                    firstItemID: firstItemID,
                    contentInsets: contentInsets,
                    proxy: proxy
                )
            )
            .task(id: scroll) {
                if scroll.kind == .top, let firstItemID {
                    proxy.scrollTo(firstItemID, anchor: .top)
                }
            }
        }
    }
}

private struct GridSelectionFrameKey: PreferenceKey {
    static var defaultValue: CGRect? { nil }

    static func reduce(value: inout CGRect?, nextValue: () -> CGRect?) {
        value = value ?? nextValue()
    }
}

private struct GridSelectionBand: Equatable {
    let top: CGFloat
    let bottom: CGFloat
}

private struct GridSelectionFollowing: ViewModifier {
    let scroll: ListScrollIntent
    let selectedRowID: String?
    let firstItemID: String?
    let contentInsets: EdgeInsets
    let proxy: ScrollViewProxy

    @State private var selectedFrame: CGRect?
    @State private var band = GridSelectionBand(top: 0, bottom: 0)
    @State private var following = false

    func body(content: Content) -> some View {
        content
            .onPreferenceChange(GridSelectionFrameKey.self) { frame in
                selectedFrame = frame
                align()
            }
            .onScrollGeometryChange(for: GridSelectionBand.self) {
                GridSelectionBand(
                    top: $0.contentInsets.top,
                    bottom: $0.containerSize.height - $0.contentInsets.bottom
                )
            } action: { _, newBand in
                band = newBand
                align()
            }
            .onChange(of: scroll) { _, value in
                switch value.kind {
                case .top:
                    following = false
                    if let firstItemID { proxy.scrollTo(firstItemID, anchor: .top) }
                case .follow:
                    following = true
                    align()
                }
            }
            .onAppear {
                if scroll.kind == .follow {
                    following = true
                    align()
                }
            }
    }

    private func align() {
        guard following, let selectedRowID, let selectedFrame else { return }
        let top = selectedFrame.minY - band.top
        let bottom = selectedFrame.maxY - band.top
        let visibleHeight = band.bottom - band.top
        switch SelectionReveal.edge(rowTop: top, rowBottom: bottom, band: visibleHeight) {
        case .top:
            proxy.scrollTo(selectedRowID, anchor: .top)
        case .bottom:
            proxy.scrollTo(selectedRowID, anchor: .bottom)
        case nil:
            following = false
        }
    }
}

private struct PaletteGridRow<Item, Cell: View>: View {
    let row: PaletteGridRowModel<Item>
    let columns: Int
    let selection: Int
    let columnSpacing: CGFloat
    let minimumCellHeight: CGFloat
    let onSelect: (Int) -> Void
    let onActivate: (Int) -> Void
    let onActions: (Int) -> Void
    @ViewBuilder let cell: (Item, Bool, Bool) -> Cell

    @EnvironmentObject private var palette: PaletteViewModel
    @State private var hoveredColumn: Int?
    @State private var width: CGFloat = 0

    var body: some View {
        HStack(spacing: columnSpacing) {
            ForEach(0..<columns, id: \.self) { column in
                if column < row.items.count {
                    cell(
                        row.items[column], row.start + column == selection,
                        column == hoveredColumn
                    )
                    .frame(maxWidth: .infinity)
                } else {
                    Color.clear
                        .frame(maxWidth: .infinity)
                        .frame(minHeight: minimumCellHeight)
                }
            }
        }
        .contentShape(Rectangle())
        .overlay {
            GeometryReader { geometry in
                Color.clear.preference(
                    key: GridSelectionFrameKey.self,
                    value: row.start <= selection && selection < row.start + row.items.count
                        ? geometry.frame(in: .scrollView)
                        : nil
                )
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .gesture(
            SpatialTapGesture().onEnded { value in
                if let index = index(at: value.location) { onSelect(index) }
            }
        )
        .simultaneousGesture(
            SpatialTapGesture(count: 2).onEnded { value in
                guard let index = index(at: value.location) else { return }
                onSelect(index)
                onActivate(index)
            }
        )
        .onRightClick { point in
            if let index = index(at: point) { onActions(index) }
        }
        .onContinuousHover(coordinateSpace: .local) { phase in
            switch phase {
            case .active(let point):
                hoveredColumn = palette.hoverHighlightArmed ? column(at: point) : nil
            case .ended:
                hoveredColumn = nil
            }
        }
    }

    private func index(at point: CGPoint) -> Int? {
        guard let column = column(at: point), column < row.items.count else { return nil }
        return row.start + column
    }

    private func column(at point: CGPoint) -> Int? {
        guard width > 0, point.x >= 0, point.x < width else { return nil }
        let cellWidth = (width - columnSpacing * CGFloat(columns - 1)) / CGFloat(columns)
        guard cellWidth > 0 else { return nil }
        let stride = cellWidth + columnSpacing
        let column = min(Int(point.x / stride), columns - 1)
        let localX = point.x - CGFloat(column) * stride
        return localX <= cellWidth ? column : nil
    }
}
