@MainActor
final class CalculatorCoordinator {
    private let hidePalette: (Bool) -> Void

    init(hidePalette: @escaping (Bool) -> Void) {
        self.hidePalette = hidePalette
    }

    func copy(_ result: CalcResult) {
        guard case .value(_, let copyText) = result.payload else { return }
        hidePalette(false)
        Paster.copyPlainText(copyText)
    }
}
