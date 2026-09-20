import Foundation

@main
struct WebURLTests {
    static func main() {
        for value in [
            "https://example.com", " HTTP://example.com/path?q=a#b ",
            "https://example.com/a%20b", "http://localhost:8080", "http://[::1]:8080",
        ] {
            precondition(WebURLResolver.resolve(value) != nil, value)
        }
        for value in [
            "", "example.com", "https://", "https:///path", "javascript:alert(1)",
            "file:///tmp/test", "https://example.com\n/path", "https://example.com/a b",
            "https://example.com:99999", "https://example.com:abc", "hello https://example.com",
        ] {
            precondition(WebURLResolver.resolve(value) == nil, value)
        }
        print("web URL tests passed")
    }
}
