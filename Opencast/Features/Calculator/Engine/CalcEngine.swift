import Foundation

/// A single evaluated calculator answer for the launcher's inline card.
struct CalcResult: Equatable, Sendable {
    enum Payload: Equatable, Sendable {
        /// `display` is grouped and human-facing ("1,234,567"); `copyText` is the same answer without grouping, for pasting onwards.
        case value(display: String, copyText: String)
        /// A friendly error ("Cannot convert Weight to Time.") — only for a clear conversion attempt, never a half-typed expression.
        case error(message: String)
    }

    /// Normalized echo of what was evaluated, shown on the card's left side ("3×3", "10 km").
    let expression: String
    /// Optional word-name pills beneath each side of the card ("Meters"→"Feet", "12:18 AM"→"9:00 AM"); nil for plain arithmetic.
    let sourceBadge: String?
    let targetBadge: String?
    let payload: Payload

    init(expression: String, sourceBadge: String? = nil, targetBadge: String? = nil, payload: Payload) {
        self.expression = expression
        self.sourceBadge = sourceBadge
        self.targetBadge = targetBadge
        self.payload = payload
    }

    /// True only for a copyable value — error cards are informational and have no primary action or actions menu.
    var isActionable: Bool {
        if case .value = payload { return true }
        return false
    }
}

/// Entry point turning a raw query into a calculator answer (or nil when it isn't calculator input), via a pure pre-filter → base → unit → arithmetic pipeline; kept Foundation-only so `Tools/calc-test.swift` compiles it standalone.
enum CalcEngine {
    /// Public entry: evaluates against the live clock. `currency` defaults to `.off` so any caller that
    /// hasn't been handed a consented source gets the feature disabled rather than silently enabled.
    static func evaluate(_ raw: String, currency: CurrencySource = .off) -> CalcResult? {
        var calendar = Calendar.current
        calendar.locale = Locale(identifier: "en_US_POSIX")
        return evaluate(raw, now: Date(), calendar: calendar, currency: currency)
    }

    /// `now`/`calendar` are injected so the date/time paths are deterministic under `Tools/calc-test.swift`.
    static func evaluate(
        _ raw: String, now: Date, calendar: Calendar, currency: CurrencySource = .off
    ) -> CalcResult? {
        let query = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, query.count <= 256 else { return nil }
        let locale = calendar.locale ?? Locale.current

        // Date/time first: `hrs till july` carries no digit, so it must run before the numeric reject below.
        if let dateTime = CalcDateTime.evaluate(query, now: now, calendar: calendar) { return dateTime }

        guard let tokens = CalcTokenizer.tokenize(query), !tokens.isEmpty else { return nil }

        if let natural = naturalMath(tokens, query: query, locale: locale) { return natural }
        if let timespan = timespanConversion(tokens, query: query, locale: locale) { return timespan }
        if let quantity = CalcQuantity.evaluate(
            tokens, query: query, currency: currency, locale: locale
        ) {
            return quantity
        }

        // A lone literal or constant is more likely an app search than a calculation, so no card — except radix and scientific literals, which are explicit numeric expressions.
        if tokens.count == 1 {
            if case .intLiteral(let value, let radix) = tokens[0], radix != 10 {
                let display = CalcFormatter.grouped(String(value), locale: locale)
                return CalcResult(
                    expression: query,
                    sourceBadge: "Hexadecimal", targetBadge: "Decimal",
                    payload: .value(display: display, copyText: String(value)))
            }
            guard case .number = tokens[0], query.contains(where: { $0 == "e" || $0 == "E" }) else {
                return nil
            }
        }

        if let base = baseConversion(tokens, query: query, locale: locale) { return base }

        // Conversions run before the numeric reject below: `m to ft`, `day s` carry no digit.
        if let conversion = CalcUnits.parseConversion(tokens) ?? CalcUnits.parseUnitPairConversion(tokens) {
            switch conversion {
            case .value(_, let from, let to, let output):
                return CalcResult(
                    expression: query,
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: "\(CalcFormatter.display(output, locale: locale)) \(to.symbol)",
                        copyText: "\(CalcFormatter.copyText(output)) \(to.symbol)"))
            case .mismatch:
                return nil
            }
        }

        // Currency runs after units so an all-unit query keeps winning: `10 pounds to kg` is weight,
        // `10 pounds to euros` is money. Returns nil outright when the user hasn't consented.
        if let conversion = CalcCurrency.parseConversion(tokens, source: currency) {
            switch conversion {
            case .value(_, let from, let to, let output):
                let amount = CalcFormatter.currency(output, locale: locale)
                let display = CalcFormatter.currencyDisplay(
                    amount: CalcFormatter.groupedLocalized(amount, locale: locale),
                    code: to.code, symbol: to.symbol, locale: locale)
                let copyAmount = CalcFormatter.currencyCopyText(output)
                return CalcResult(
                    expression: query,
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: display,
                        copyText: "\(copyAmount) \(to.code)"))
            case .mismatch:
                return nil
            case .noRate(let code):
                return CalcResult(
                    expression: query,
                    payload: .error(message: "No exchange rate for \(code)."))
            case .unavailable:
                return CalcResult(
                    expression: query,
                    payload: .error(message: "Exchange rates unavailable — check your connection."))
            }
        }

        // Keyword-less conversion: `1m` → feet+inches, `1hr` → 60 min.
        if let bare = CalcUnits.parseBareConversion(tokens) {
            let display =
                bare.compound
                ? CalcFormatter.compoundFeetInches(bare.output, locale: locale)
                : "\(CalcFormatter.display(bare.output, locale: locale)) \(bare.to.symbol)"
            let copyText =
                bare.compound
                ? display : "\(CalcFormatter.copyText(bare.output)) \(bare.to.symbol)"
            return CalcResult(
                expression: "\(CalcFormatter.display(bare.input, locale: locale)) \(bare.from.symbol)",
                sourceBadge: bare.from.name,
                targetBadge: bare.to.name,
                payload: .value(display: display, copyText: copyText))
        }

        // A bare currency amount targets the user's locale currency: `20$`, `20 usd`, `20€`.
        if let targetCode = locale.currency?.identifier,
            let conversion = CalcCurrency.parseDefaultConversion(
                tokens, source: currency, targetCode: targetCode)
        {
            switch conversion {
            case .value(_, let from, let to, let output):
                let amount = CalcFormatter.currency(output, locale: locale)
                let display = CalcFormatter.currencyDisplay(
                    amount: CalcFormatter.groupedLocalized(amount, locale: locale),
                    code: to.code, symbol: to.symbol, locale: locale)
                let copyAmount = CalcFormatter.currencyCopyText(output)
                return CalcResult(
                    expression: query,
                    sourceBadge: from.name,
                    targetBadge: to.name,
                    payload: .value(
                        display: display,
                        copyText: "\(copyAmount) \(to.code)"))
            case .noRate(let code):
                return CalcResult(
                    expression: query,
                    payload: .error(message: "No exchange rate for \(code)."))
            case .unavailable:
                return CalcResult(
                    expression: query,
                    payload: .error(message: "Exchange rates unavailable — check your connection."))
            case .mismatch:
                return nil
            }
        }

        // Natural-language percent: `20% off 500`, `50 as % of 200`.
        if let percent = CalcPercent.evaluate(tokens, query: query, locale: locale) { return percent }

        // Cheap reject for the arithmetic fallback: plain math always carries a digit or a constant, keeping the common app-search case a no-card.
        guard
            query.contains(where: { $0.isASCII && $0.isNumber })
                || query.lowercased().contains("e") || query.contains("π")
        else { return nil }

        guard let value = CalcParser.evaluate(tokens) else { return nil }
        return CalcResult(
            expression: prettyExpression(query),
            sourceBadge: "Expression",
            targetBadge: "Result",
            payload: .value(
                display: CalcFormatter.display(value, locale: locale),
                copyText: CalcFormatter.copyText(value)))
    }

    // MARK: - Natural language math and timespans

    private static func naturalMath(
        _ tokens: [CalcToken], query: String, locale: Locale
    ) -> CalcResult? {
        let rootPrefixes: [[CalcToken]] = [
            [.ident("square"), .ident("root"), .ident("of")],
            [.ident("cube"), .ident("root"), .ident("of")],
            [.ident("root"), .ident("of")],
        ]
        for prefix in rootPrefixes where tokens.starts(with: prefix) {
            let valueTokens = Array(tokens.dropFirst(prefix.count))
            guard let value = CalcParser.evaluate(valueTokens) else { return nil }
            let root = prefix.first == .ident("cube") ? 3.0 : 2.0
            let result = pow(value, 1 / root)
            guard result.isFinite else { return nil }
            return CalcResult(
                expression: query, sourceBadge: "Expression", targetBadge: "Result",
                payload: .value(
                    display: CalcFormatter.display(result, locale: locale),
                    copyText: CalcFormatter.copyText(result)))
        }

        guard let power = tokens.firstIndex(of: .ident("power")) else { return nil }
        var left = Array(tokens[..<power])
        if left.last == .ident("to") { left.removeLast() }
        let right = Array(tokens[(power + 1)...])
        guard !left.isEmpty, !right.isEmpty,
            let base = CalcParser.evaluate(left), let exponent = CalcParser.evaluate(right)
        else { return nil }
        let result = Foundation.pow(base, exponent)
        guard result.isFinite else { return nil }
        return CalcResult(
            expression: query, sourceBadge: "Expression", targetBadge: "Result",
            payload: .value(
                display: CalcFormatter.display(result, locale: locale),
                copyText: CalcFormatter.copyText(result)))
    }

    private static func timespanConversion(
        _ tokens: [CalcToken], query: String, locale: Locale
    ) -> CalcResult? {
        guard let connector = tokens.lastIndex(where: CalcUnits.isConnector),
            connector > 0, connector + 1 < tokens.count,
            tokens[connector + 1] == .ident("timespan")
        else { return nil }

        let left = Array(tokens[..<connector])
        guard
            let sourceIndex = left.lastIndex(where: { token in
                guard case .ident(let name) = token else { return false }
                return CalcUnits.byName[name]?.category == .time
            }),
            case .ident(let sourceName) = left[sourceIndex],
            let source = CalcUnits.byName[sourceName]
        else { return nil }

        let valueTokens = Array(left[..<sourceIndex])
        let input = valueTokens.isEmpty ? 1 : CalcParser.evaluate(valueTokens)
        guard let input else { return nil }
        let seconds = input * source.factor
        guard seconds.isFinite else { return nil }
        let display = formatTimespan(seconds, locale: locale)
        return CalcResult(
            expression: query, sourceBadge: source.name, targetBadge: "Timespan",
            payload: .value(display: display, copyText: display))
    }

    private static func formatTimespan(_ seconds: Double, locale: Locale) -> String {
        let sign = seconds < 0 ? "-" : ""
        var remaining = abs(seconds)
        var parts: [String] = []
        let units: [(Double, String, String)] = [
            (86_400, "day", "days"), (3_600, "hr", "hrs"),
            (60, "min", "mins"), (1, "sec", "secs"),
        ]
        for (size, singular, plural) in units {
            guard remaining >= size else { continue }
            let value = floor(remaining / size)
            remaining -= value * size
            parts.append("\(CalcFormatter.display(value, locale: locale)) \(value == 1 ? singular : plural)")
        }
        if parts.isEmpty {
            parts.append("\(CalcFormatter.display(seconds, locale: locale)) sec")
        }
        return sign + parts.joined(separator: " ")
    }

    // MARK: - Number bases

    /// `255 to hex`, `0xff to decimal`, `0b1010 to binary`, `2*128 to hex` — value expression, connector, target.
    private static func baseConversion(
        _ tokens: [CalcToken], query: String, locale: Locale
    ) -> CalcResult? {
        guard tokens.count >= 3,
            CalcUnits.isConnector(tokens[tokens.count - 2]),
            case .ident(let target) = tokens[tokens.count - 1]
        else { return nil }

        let valueTokens = Array(tokens[0..<(tokens.count - 2)])
        let literalText = query.split(whereSeparator: \.isWhitespace).first.map(String.init) ?? query
        let source: UInt64
        let sourceBadge: String
        let sourceText: String
        if valueTokens.count == 1,
            case .intLiteral(let value, let radix) = valueTokens[0]
        {
            source = value
            sourceBadge = baseName(forRadix: radix)
            sourceText = literalText
        } else if valueTokens.count == 1,
            let value = decimalLiteral(valueTokens[0]),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = literalText
        } else if let value = CalcParser.evaluate(valueTokens),
            value >= 0, value.rounded() == value, value <= 9_007_199_254_740_992
        {
            source = UInt64(value)
            sourceBadge = "Decimal"
            sourceText = CalcFormatter.grouped(String(source), locale: locale)
        } else {
            return nil
        }

        let output: String
        let targetBadge: String
        switch target {
        case "hex", "hexadecimal":
            output = "0x" + String(source, radix: 16, uppercase: true)
            targetBadge = "Hexadecimal"
        case "binary", "bin":
            output = "0b" + String(source, radix: 2)
            targetBadge = "Binary"
        case "octal", "oct":
            output = "0o" + String(source, radix: 8)
            targetBadge = "Octal"
        case "decimal", "dec":
            output = CalcFormatter.grouped(String(source), locale: locale)
            targetBadge = "Decimal"
        default:
            return nil
        }
        return CalcResult(
            expression: sourceText,
            sourceBadge: sourceBadge,
            targetBadge: targetBadge,
            payload: .value(
                display: output, copyText: output.replacingOccurrences(of: ",", with: "")))
    }

    private static func decimalLiteral(_ token: CalcToken) -> Double? {
        switch token {
        case .number(let value): return value
        default: return nil
        }
    }

    private static func baseName(forRadix radix: Int) -> String {
        switch radix {
        case 16: return "Hexadecimal"
        case 2: return "Binary"
        case 8: return "Octal"
        default: return "Decimal"
        }
    }

    /// Light cleanup of the typed expression for the card: collapse whitespace and use pretty operator glyphs, otherwise keep what the user wrote.
    private static func prettyExpression(_ query: String) -> String {
        query.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            .replacingOccurrences(of: "*", with: "×")
            .replacingOccurrences(of: "/", with: "÷")
    }
}
