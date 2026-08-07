import SwiftUI

@MainActor
protocol PaletteScreen: View {
    var itemCount: Int { get }
    var actionsContent: PopoverMenuContent? { get }

    @discardableResult
    func activate() -> Bool
}
