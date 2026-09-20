import Foundation

enum SnippetExpansionMatch {
    static func keyword(in buffer: String, keywords: [String], afterSpace: Bool) -> String? {
        if afterSpace && !buffer.hasSuffix(" ") { return nil }
        let typed = afterSpace ? String(buffer.dropLast()) : buffer
        return keywords.filter { keyword in
            guard !keyword.isEmpty, typed.hasSuffix(keyword) else { return false }
            guard let previous = typed.dropLast(keyword.count).last else { return true }
            return !previous.isLetter && !previous.isNumber
        }.max { $0.count < $1.count }
    }
}
