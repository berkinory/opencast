import Foundation

@main
@MainActor
struct PaletteSelectionTests {
    static var failures = 0
    static var passes = 0

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    static func expectRoundTrip(_ index: PaletteSelectionIndex, _ label: String) {
        for flat in 0..<index.count {
            guard let row = index.row(at: flat) else {
                expect(false, "\(label): index \(flat) resolves")
                continue
            }
            switch row {
            case .calculator:
                expect(flat == 0, "\(label): calculator stays at index zero")
            case .element(let section, let offset):
                expect(
                    index.index(section: section, offset: offset) == flat,
                    "\(label): row inverts to its original index")
            }
        }
    }

    static func main() {
        let empty = PaletteSelectionIndex(sectionCounts: [])
        expect(empty.count == 0, "empty sections have no selectable rows")
        expect(empty.clamped(Int.max) == 0, "empty selection clamps to zero")
        expect(empty.row(at: 0) == nil, "empty index resolves no row")
        expect(empty.shortcutIndex(digit: 1) == nil, "empty results have no numeric shortcut")
        let shortcuts = PaletteSelectionIndex(hasCalculator: true, sectionCounts: [4, 6])
        for digit in 1...9 {
            expect(shortcuts.shortcutIndex(digit: digit) == digit - 1, "shortcut follows flat visible result order")
        }
        expect(shortcuts.shortcutIndex(digit: 0) == nil, "Command-0 is not bound")
        expect(shortcuts.shortcutIndex(digit: 10) == nil, "only nine shortcuts exist")
        expect(
            PaletteSelectionIndex(sectionCounts: [2]).shortcutIndex(digit: 3) == nil,
            "shortcut cannot activate a missing row")

        let launcher = PaletteSelectionIndex(hasCalculator: true, sectionCounts: [3, 2])
        expect(launcher.count == 6, "calculator plus five rows")
        expect(launcher.row(at: 0) == .calculator, "calculator is the first row")
        expect(
            launcher.row(at: 4) == .element(section: 1, offset: 0),
            "section boundaries do not consume a selection")
        expect(launcher.index(section: 1, offset: 1) == 5, "inverse index includes calculator offset")
        expectRoundTrip(launcher, "launcher")

        let gapped = PaletteSelectionIndex(sectionCounts: [2, 0, 2])
        expect(gapped.count == 4, "empty sections contribute no rows")
        expect(gapped.row(at: 2) == .element(section: 2, offset: 0), "empty section is skipped")
        expect(gapped.index(section: 1, offset: 0) == nil, "empty section has no valid offset")
        expectRoundTrip(gapped, "gapped sections")

        for hasCalculator in [false, true] {
            for a in 0...3 {
                for b in 0...3 {
                    for c in 0...3 {
                        let index = PaletteSelectionIndex(
                            hasCalculator: hasCalculator, sectionCounts: [a, b, c])
                        expectRoundTrip(index, "shape \(hasCalculator) [\(a),\(b),\(c)]")
                        if index.count > 0 {
                            expect(index.row(at: index.clamped(Int.min)) != nil, "negative clamp resolves")
                            expect(index.row(at: index.clamped(Int.max)) != nil, "positive clamp resolves")
                        }
                    }
                }
            }
        }

        print("\(passes) passed, \(failures) failed")
        if failures > 0 { exit(1) }
    }
}
