import Foundation

/// Hand-rolled number formatting with an injected locale for display; copy text remains plain POSIX notation so answers can be pasted into another calculation.
enum CalcFormatter {
    private static let maxExactInteger = 9_007_199_254_740_992.0

    /// Human-facing: ≤10 significant digits, trailing zeros trimmed, thousands separators.
    static func display(_ value: Double, locale: Locale = Locale(identifier: "en_US_POSIX")) -> String {
        grouped(copyText(value), locale: locale)
    }

    /// Same rounding, no grouping — what lands on the pasteboard.
    static func copyText(_ value: Double) -> String {
        let v = value == 0 ? 0 : value  // normalize -0
        // Past 2^53 the precision is genuinely gone, so exponent form is the honest answer there.
        if v.rounded() == v && abs(v) <= maxExactInteger {
            return String(format: "%.0f", locale: Locale(identifier: "en_US_POSIX"), v)
        }
        return String(format: "%.10g", locale: Locale(identifier: "en_US_POSIX"), v)
    }

    /// Money rounding for currency answers: two decimals, widening to four significant digits below a cent so a small cross-rate never collapses to "0.00". Deliberately not `%g` — a satoshi-scale rate must read "0.00001551", never "1.551e-05". Ungrouped; the display side wraps this in `grouped`.
    static func currency(
        _ value: Double, locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let magnitude = abs(value)
        guard magnitude >= 1e-9 else { return localized("0.00", locale: locale) }
        if magnitude < 0.01 {
            var text = String(
                format: "%.\(3 - Int(floor(log10(magnitude))))f",
                locale: Locale(identifier: "en_US_POSIX"), value)
            while text.hasSuffix("0") { text.removeLast() }
            return localized(text, locale: locale)
        }
        return localized(
            String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value),
            locale: locale)
    }

    static func currencyDisplay(
        amount: String, code: String, symbol: String? = nil, locale: Locale
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .currency
        formatter.currencyCode = code
        let symbol = symbol ?? formatter.currencySymbol ?? code
        guard symbol != code else { return "\(amount) \(code)" }

        let isNegative = amount.hasPrefix("-")
        let magnitude = isNegative ? String(amount.dropFirst()) : amount
        let prefix =
            (isNegative ? (formatter.negativePrefix ?? "-") : (formatter.positivePrefix ?? ""))
            .trimmingCharacters(in: .whitespaces)
        let suffix = isNegative ? (formatter.negativeSuffix ?? "") : (formatter.positiveSuffix ?? "")
        return "\(prefix)\(magnitude)\(suffix)"
    }

    static func currencyCopyText(_ value: Double) -> String {
        let magnitude = abs(value)
        guard magnitude >= 1e-9 else { return "0.00" }
        guard magnitude >= 0.01 else {
            var text = String(
                format: "%.\(3 - Int(floor(log10(magnitude))))f",
                locale: Locale(identifier: "en_US_POSIX"), value)
            while text.hasSuffix("0") { text.removeLast() }
            return text
        }
        return String(format: "%.2f", locale: Locale(identifier: "en_US_POSIX"), value)
    }

    /// A length in feet rendered as whole feet + remaining inches ("3 feet 3.370078740 inches"); used only for the bare metric-length auto-conversion. Sub-foot values drop the feet part.
    static func compoundFeetInches(
        _ feet: Double, locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let sign = feet < 0 ? "-" : ""
        let magnitude = abs(feet)
        let wholeFeet = magnitude.rounded(.towardZero)
        let inches = (magnitude - wholeFeet) * 12
        let feetPart =
            wholeFeet == 0
            ? ""
            : "\(sign)\(display(wholeFeet, locale: locale)) \(wholeFeet == 1 ? "foot" : "feet")"
        let inchText = display(inches, locale: locale)
        let inchPart = "\(inchText) \(inchText == "1" ? "inch" : "inches")"
        if feetPart.isEmpty { return "\(sign)\(inchPart)" }
        return "\(feetPart) \(inchPart)"
    }

    /// Insert `,` every three integer digits. Exponent-form strings pass through untouched.
    static func grouped(
        _ text: String, locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        guard !text.contains("e"), !text.contains("E") else { return text }
        let sign = text.hasPrefix("-") ? "-" : ""
        let unsigned = sign.isEmpty ? text : String(text.dropFirst())
        let parts = unsigned.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let intDigits = Array(parts[0])
        var groupedInt = ""
        for (i, digit) in intDigits.enumerated() {
            if intDigits.count > 3 && i > 0
                && (intDigits.count - i) % 3 == 0
            {
                groupedInt.append(",")
            }
            groupedInt.append(digit)
        }
        let fraction = parts.count > 1 ? "." + parts[1] : ""
        return localized(sign + groupedInt + fraction, locale: locale)
    }

    static func groupedLocalized(
        _ text: String, locale: Locale = Locale(identifier: "en_US_POSIX")
    ) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        let decimalSeparator = formatter.decimalSeparator ?? "."
        let groupingSeparator = formatter.groupingSeparator ?? ","
        let canonical =
            text.replacingOccurrences(of: groupingSeparator, with: "")
            .replacingOccurrences(of: decimalSeparator, with: ".")
        return grouped(canonical, locale: locale)
    }

    private static func localized(_ text: String, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        let decimalSeparator = formatter.decimalSeparator ?? "."
        let groupingSeparator = formatter.groupingSeparator ?? ","
        let parts = text.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
        let integer = parts[0].replacingOccurrences(of: ",", with: groupingSeparator)
        guard parts.count == 2 else { return integer }
        return integer + decimalSeparator + parts[1]
    }
}
