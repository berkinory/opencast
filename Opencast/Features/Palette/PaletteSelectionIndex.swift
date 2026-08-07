import Foundation

enum PaletteSelectionRow: Equatable {
    case calculator
    case element(section: Int, offset: Int)
}

struct PaletteSelectionIndex: Equatable {
    let hasCalculator: Bool
    let sectionCounts: [Int]

    init(hasCalculator: Bool = false, sectionCounts: [Int]) {
        self.hasCalculator = hasCalculator
        self.sectionCounts = sectionCounts
    }

    var count: Int {
        (hasCalculator ? 1 : 0) + sectionCounts.reduce(0, +)
    }

    func clamped(_ selection: Int) -> Int {
        count == 0 ? 0 : min(max(selection, 0), count - 1)
    }

    func row(at index: Int) -> PaletteSelectionRow? {
        guard index >= 0, index < count else { return nil }
        if hasCalculator, index == 0 { return .calculator }

        var offset = hasCalculator ? index - 1 : index
        for (section, sectionCount) in sectionCounts.enumerated() {
            if offset < sectionCount {
                return .element(section: section, offset: offset)
            }
            offset -= sectionCount
        }
        return nil
    }

    func index(section: Int, offset: Int) -> Int? {
        guard sectionCounts.indices.contains(section), offset >= 0,
            offset < sectionCounts[section]
        else { return nil }
        let preceding = sectionCounts[..<section].reduce(0, +)
        return (hasCalculator ? 1 : 0) + preceding + offset
    }
}
