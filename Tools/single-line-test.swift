import Foundation

@main
struct SingleLineTests {
    static func main() {
        for separator in ["\n", "\r", "\r\n", "\u{2028}", "\u{2029}", "\u{0085}"] {
            precondition(SingleLineText.collapse("first" + separator + "second") == "first second")
        }
        precondition(SingleLineText.collapse("hello  world ") == "hello  world ")
        precondition(SingleLineText.collapse("hello👩🏽‍💻") == "hello👩🏽‍💻")
        precondition(SingleLineText.collapse("") == "")
        print("single-line input tests passed")
    }
}
