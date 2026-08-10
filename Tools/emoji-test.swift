// Standalone test for the emoji catalog — compiles the real Foundation-only sources.
// swiftc Opencast/Features/Emoji/EmojiCatalog.swift Opencast/Features/Emoji/EmojiData.generated.swift Tools/emoji-test.swift -o /tmp/emoji-test && /tmp/emoji-test

import Foundation

@main
struct EmojiTests {
    static var failures = 0

    static func expect(_ condition: Bool, _ label: String) {
        if !condition {
            print("FAIL: \(label)")
            failures += 1
        }
    }

    static func main() {
        // Dataset + parser
        let entries = EmojiCatalog.parse(EmojiData.raw)
        expect(entries.count > 1900, "dataset has \(entries.count) records (want > 1900)")
        expect(Set(entries.map(\.glyph)).count == entries.count, "glyphs are unique")
        expect(
            Set(entries.map(\.category)).count == EmojiCategory.allCases.count,
            "every category is populated")

        let wave = entries.first { $0.name == "waving hand" }
        expect(wave?.supportsSkinTone == true, "👋 is tone-capable")
        expect(wave?.keywords.contains("hello") == true, "👋 carries CLDR keywords")
        let holdingHands = entries.first { $0.glyph == "🧑‍🤝‍🧑" }
        expect(holdingHands?.supportsSkinTone == false, "multi-person ZWJ is not tone-capable")
        let euro = entries.first { $0.glyph == "€" }
        expect(euro?.category == .currency, "€ landed in Currency")

        // Skin tone application
        expect(EmojiCatalog.applyTone(.dark, to: "👋") == "👋🏿", "modifier appended")
        let victory = entries.first { $0.name == "victory hand" }!
        expect(victory.glyph.unicodeScalars.contains { $0.value == 0xFE0F }, "✌️ base carries VS16")
        let toned = victory.display(tone: .light)
        expect(
            !toned.unicodeScalars.contains { $0.value == 0xFE0F }
                && toned.unicodeScalars.contains { $0.value == 0x1F3FB },
            "tone strips VS16 and appends the modifier")
        expect(victory.display(tone: .none) == victory.glyph, "tone .none leaves the glyph alone")
        expect(
            holdingHands!.display(tone: .dark) == holdingHands!.glyph,
            "tone ignored on non-capable entries")

        if failures == 0 {
            print("emoji-test: all checks passed (\(entries.count) records)")
        } else {
            print("emoji-test: \(failures) failure(s)")
            exit(1)
        }
    }
}
