import CoreGraphics

struct PaletteGridGeometry {
    let counts: [Int]
    let columns: Int
    private let starts: [Int]

    init(counts: [Int], columns: Int) {
        precondition(columns > 0)
        self.counts = counts
        self.columns = columns
        var starts: [Int] = []
        var running = 0
        for count in counts {
            starts.append(running)
            running += count
        }
        self.starts = starts
    }

    func down(from selection: Int) -> Int {
        guard let section = section(containing: selection) else { return selection }
        let local = selection - starts[section]
        let candidate = local + columns
        if candidate < counts[section] { return starts[section] + candidate }
        if local / columns < (counts[section] - 1) / columns {
            return starts[section] + counts[section] - 1
        }
        guard section + 1 < counts.count else { return selection }
        return starts[section + 1] + min(local % columns, counts[section + 1] - 1)
    }

    func up(from selection: Int) -> Int {
        guard let section = section(containing: selection) else { return selection }
        let local = selection - starts[section]
        if local - columns >= 0 { return starts[section] + local - columns }
        guard section > 0 else { return selection }
        let previousCount = counts[section - 1]
        let lastRowStart = ((previousCount - 1) / columns) * columns
        return starts[section - 1] + min(lastRowStart + local % columns, previousCount - 1)
    }

    private func section(containing selection: Int) -> Int? {
        for (index, start) in starts.enumerated().reversed() where selection >= start {
            return counts[index] > 0 && selection < start + counts[index] ? index : nil
        }
        return nil
    }
}

enum SelectionReveal {
    enum Edge: Equatable {
        case top
        case bottom
    }

    static func edge(rowTop: CGFloat, rowBottom: CGFloat, band: CGFloat) -> Edge? {
        guard band > 0 else { return nil }
        if rowTop <= 0 && rowBottom >= band { return nil }
        if rowTop < 0 { return .top }
        if rowBottom > band { return .bottom }
        return nil
    }
}
