import Foundation

@main
struct SnippetExpansionTests {
    static func main() {
        let keywords = ["!mail", "!mailwork", ""]
        func match(_ buffer: String, afterSpace: Bool = true) -> String? {
            SnippetExpansionMatch.keyword(in: buffer, keywords: keywords, afterSpace: afterSpace)
        }
        precondition(match("!mail") == nil)
        precondition(match("!mailwork ") == "!mailwork")
        precondition(match("!mail ") == "!mail")
        precondition(match("hello !mail ") == "!mail")
        precondition(match("word!mail ") == nil)
        precondition(match("!mail\n") == nil)
        precondition(match("!mail", afterSpace: false) == "!mail")
        precondition(match("", afterSpace: false) == nil)
        precondition(match("!mailwork", afterSpace: false) == "!mailwork")
        print("snippet expansion tests passed")
    }
}
