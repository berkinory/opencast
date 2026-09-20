import Foundation

enum SingleLineText {
    static func collapse(_ text: String) -> String {
        String(text.map { $0.isNewline ? " " : $0 })
    }
}
