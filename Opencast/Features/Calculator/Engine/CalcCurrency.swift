import Foundation

/// One currency: the ISO 4217 code shown next to the amount and the long label used as a card badge.
struct CurrencyDef: Equatable, Sendable {
    let code: String  // "EUR"
    let name: String  // "Euro"
    let symbol: String?
}

/// An exchange-rate snapshot: every rate quoted as units of that currency per 1 `base`. Downloaded and persisted by `CurrencyRateStore` and handed to `CalcEngine.evaluate` — the engine never fetches, which is what keeps `Core/Calculator/` Foundation-only and pure.
struct CurrencyRates: Codable, Equatable, Sendable {
    let base: String
    let rates: [String: Double]
    /// When this table was downloaded — drives staleness, and doubles as the memo key in `CalcMemo`.
    let fetchedAt: Date

    func rate(for code: String) -> Double? {
        if let rate = rates[code], rate > 0, rate.isFinite { return rate }
        return code == base ? 1 : nil
    }

    /// Cross-rate through the base currency.
    func convert(_ amount: Double, from: String, to: String) -> Double? {
        guard let source = rate(for: from), let target = rate(for: to) else { return nil }
        let output = amount / source * target
        return output.isFinite ? output : nil
    }
}

/// Whether the calculator may answer currency questions at all, and with what.
///
/// `.off` is the shipped default and the *only* state that exists without explicit user consent:
/// the currency path never engages, so a currency query falls through to no card — not an error
/// explaining a feature the user never turned on. `.on(nil)` means consent was given but no
/// snapshot has landed yet, which is the state that earns the "rates unavailable" message.
enum CurrencySource: Equatable, Sendable {
    case off
    case on(CurrencyRates?)
    case onWithCrypto(CurrencyRates?, cryptoEnabled: Bool)

    var isOn: Bool {
        switch self {
        case .off: return false
        case .on, .onWithCrypto: return true
        }
    }

    var rates: CurrencyRates? {
        switch self {
        case .off: return nil
        case .on(let rates), .onWithCrypto(let rates, _): return rates
        }
    }

    var cryptoEnabled: Bool {
        switch self {
        case .off, .on: return true
        case .onWithCrypto(_, let enabled): return enabled
        }
    }
}

enum CalcCurrency {
    struct CryptoAsset: Sendable {
        let code: String
        let name: String
        let id: String
        let symbol: String
        let aliases: [String]
    }

    static let cryptoAssets: [CryptoAsset] = [
        CryptoAsset(code: "BTC", name: "Bitcoin", id: "bitcoin", symbol: "₿", aliases: ["btc", "bitcoin"]),
        CryptoAsset(code: "ETH", name: "Ethereum", id: "ethereum", symbol: "Ξ", aliases: ["eth", "ethereum"]),
        CryptoAsset(code: "SOL", name: "Solana", id: "solana", symbol: "◎", aliases: ["sol", "solana"]),
        CryptoAsset(code: "BNB", name: "BNB", id: "binancecoin", symbol: "BNB", aliases: ["bnb"]),
        CryptoAsset(code: "XRP", name: "XRP", id: "ripple", symbol: "XRP", aliases: ["xrp"]),
        CryptoAsset(code: "ADA", name: "Cardano", id: "cardano", symbol: "ADA", aliases: ["ada", "cardano"]),
        CryptoAsset(code: "DOGE", name: "Dogecoin", id: "dogecoin", symbol: "Ð", aliases: ["doge", "dogecoin"]),
        CryptoAsset(code: "DOT", name: "Polkadot", id: "polkadot", symbol: "DOT", aliases: ["dot", "polkadot"]),
        CryptoAsset(
            code: "AVAX", name: "Avalanche", id: "avalanche-2", symbol: "AVAX",
            aliases: ["avax", "avalanche"]),
        CryptoAsset(
            code: "LINK", name: "Chainlink", id: "chainlink", symbol: "LINK",
            aliases: ["link", "chainlink"]),
        CryptoAsset(
            code: "LTC", name: "Litecoin", id: "litecoin", symbol: "Ł",
            aliases: ["ltc", "litecoin"]),
        CryptoAsset(
            code: "TRX", name: "TRON", id: "tron", symbol: "TRX",
            aliases: ["trx", "tron"]),
        CryptoAsset(
            code: "TON", name: "Toncoin", id: "the-open-network", symbol: "TON",
            aliases: ["ton", "toncoin"]),
        CryptoAsset(
            code: "UNI", name: "Uniswap", id: "uniswap", symbol: "UNI",
            aliases: ["uni", "uniswap"]),
        CryptoAsset(
            code: "MATIC", name: "Polygon", id: "matic-network", symbol: "MATIC",
            aliases: ["matic", "polygon"]),
    ]

    enum ConversionParse: Equatable {
        case value(input: Double, from: CurrencyDef, to: CurrencyDef, output: Double)
        /// One side is a currency, the other a measurement unit — `10 usd to kg`.
        case mismatch(from: String, to: String)
        /// Both sides are currencies but the snapshot doesn't quote one of them.
        case noRate(code: String)
        /// No snapshot has ever been downloaded (first run, still offline).
        case unavailable
    }

    /// The category label used in the mismatch message, mirroring `UnitCategory.displayName`.
    static let categoryName = "Currency"

    static func isCryptoCode(_ code: String) -> Bool {
        cryptoAssets.contains { $0.code == code }
    }

    /// Detects a currency conversion with a connector between two currency or unit phrases. Currency names may be multi-word, so `2 US dollars to Turkish lira` is resolved from the phrase boundaries rather than fixed token positions.
    static func parseConversion(_ tokens: [CalcToken], source: CurrencySource) -> ConversionParse? {
        guard source.isOn else { return nil }
        let rates = source.rates
        let tokens = amountFirst(tokens)
        guard let connector = tokens.lastIndex(where: { CalcUnits.isConnector($0) }),
            connector > 0, connector + 1 < tokens.count
        else { return nil }

        let left = Array(tokens[..<connector])
        let right = Array(tokens[(connector + 1)...])
        let fromMatch = currencySuffix(in: left)
        let to = currencyPhrase(right)

        if let fromMatch, let to {
            let valueTokens = Array(left[..<fromMatch.start])
            let input: Double
            if valueTokens.isEmpty {
                input = 1
            } else if let value = CalcParser.evaluate(valueTokens) {
                input = value
            } else {
                return nil
            }
            return converted(
                input: input,
                from: fromMatch.currency,
                to: to,
                rates: rates,
                cryptoEnabled: source.cryptoEnabled
            )
        }

        if fromMatch != nil, let unit = unitPhrase(right) {
            return .mismatch(from: categoryName, to: unit.category.displayName)
        }
        if let unit = unitSuffix(in: left), to != nil {
            return .mismatch(from: unit.category.displayName, to: categoryName)
        }
        return nil
    }

    /// Resolves a currency amount with no connector against the user's locale currency: `20$`, `20 usd`, `20€`.
    static func parseDefaultConversion(
        _ tokens: [CalcToken], source: CurrencySource, targetCode: String
    ) -> ConversionParse? {
        guard source.isOn,
            let target = byName[targetCode.lowercased()],
            let fromMatch = currencySuffix(in: amountFirst(tokens)),
            fromMatch.start > 0
        else { return nil }

        let normalized = amountFirst(tokens)
        guard let input = CalcParser.evaluate(Array(normalized[..<fromMatch.start])) else {
            return nil
        }
        return converted(
            input: input,
            from: fromMatch.currency,
            to: target,
            rates: source.rates,
            cryptoEnabled: source.cryptoEnabled
        )
    }

    private static func converted(
        input: Double, from: CurrencyDef, to: CurrencyDef, rates: CurrencyRates?,
        cryptoEnabled: Bool
    ) -> ConversionParse? {
        guard cryptoEnabled || (!isCryptoCode(from.code) && !isCryptoCode(to.code)) else {
            return nil
        }
        guard let rates else { return .unavailable }
        guard rates.rate(for: from.code) != nil else { return .noRate(code: from.code) }
        guard rates.rate(for: to.code) != nil else { return .noRate(code: to.code) }
        guard let output = rates.convert(input, from: from.code, to: to.code) else {
            return .noRate(code: to.code)
        }
        return .value(input: input, from: from, to: to, output: output)
    }

    private static func phrase<C: Collection>(_ tokens: C) -> String?
    where C.Element == CalcToken {
        let names = tokens.map { token -> String? in
            guard case .ident(let name) = token else { return nil }
            return name
        }
        guard names.allSatisfy({ $0 != nil }) else { return nil }
        return names.compactMap { $0 }.joined(separator: " ")
    }

    private static func currencyPhrase(_ tokens: [CalcToken]) -> CurrencyDef? {
        guard let name = phrase(tokens) else { return nil }
        return byPhrase[name]
    }

    private static func currencySuffix(in tokens: [CalcToken]) -> (start: Int, currency: CurrencyDef)? {
        guard !tokens.isEmpty else { return nil }
        for start in 0..<tokens.count {
            guard let name = phrase(tokens[start...]), let currency = byPhrase[name] else { continue }
            return (start, currency)
        }
        return nil
    }

    private static func unitPhrase(_ tokens: [CalcToken]) -> UnitDef? {
        guard let name = phrase(tokens) else { return nil }
        return CalcUnits.byName[name]
    }

    private static func unitSuffix(in tokens: [CalcToken]) -> UnitDef? {
        guard let token = tokens.last, case .ident(let name) = token else { return nil }
        return CalcUnits.byName[name]
    }

    /// Money is written sign-first (`€20`), so a leading currency ident followed by its amount is swapped back into the `amount currency …` order every parser here expects.
    private static func amountFirst(_ tokens: [CalcToken]) -> [CalcToken] {
        guard tokens.count >= 2, case .ident(let name) = tokens[0], byName[name] != nil,
            case .number = tokens[1]
        else { return tokens }
        var reordered = tokens
        reordered.swapAt(0, 1)
        return reordered
    }

    /// The only currency data still written by hand: nouns several currencies share, where CLDR
    /// correctly refuses to choose ("US dollars", "Canadian dollars" — never a bare "dollars") and
    /// the calculator has to. The count is how many of the feed's currencies claim that word.
    /// Everything unambiguous — names, signs, and 129 uncontested nouns — is generated.
    /// `pound`/`pounds` deliberately overlaps `CalcUnits`' weight; the pipeline order resolves it.
    private static let contested: [String: [String]] = [
        "USD": ["dollar", "dollars"],  // 22 claimants
        "CHF": ["franc", "francs"],  // 10
        "GBP": ["pound", "pounds"],  // 9
        "MXN": ["peso", "pesos"],  // 8
        "INR": ["rupee", "rupees"],  // 6
        "KES": ["shilling", "shillings"],  // 4
        "AED": ["dirham", "dirhams"],  // 2
        "KRW": ["won"],  // 2
        "RON": ["leu", "lei"],  // 2
        "RUB": ["ruble", "rubles"],  // 2
        "SAR": ["riyal", "riyals"],  // 2
    ]

    /// Lookup by lowercased ident. Codes, display names and uncontested nouns come from
    /// `CurrencyData.generated.swift`; `contested` above is applied last so its choices win.
    static let byName: [String: CurrencyDef] = {
        var defs: [String: CurrencyDef] = [:]
        var table: [String: CurrencyDef] = [:]
        defs.reserveCapacity(CurrencyData.all.count)
        table.reserveCapacity(CurrencyData.all.count + CurrencyData.aliases.count)
        for entry in CurrencyData.all {
            let def = CurrencyDef(code: entry.code, name: entry.name, symbol: nil)
            defs[entry.code] = def
            table[entry.code.lowercased()] = def
        }
        for (word, code) in CurrencyData.aliases { table[word] = defs[code] }
        for asset in cryptoAssets {
            let def = CurrencyDef(code: asset.code, name: asset.name, symbol: asset.symbol)
            defs[asset.code] = def
            table[asset.code.lowercased()] = def
            for alias in asset.aliases { table[alias] = def }
        }
        for (code, words) in contested {
            guard let def = defs[code] else { continue }
            for word in words { table[word] = def }
        }
        return table
    }()

    static func definition(for code: String) -> CurrencyDef? {
        byName[code.lowercased()]
    }

    /// Includes generated full names and their regular English plural for multi-word queries.
    private static let byPhrase: [String: CurrencyDef] = {
        var table = byName
        for entry in CurrencyData.all {
            let def = CurrencyDef(code: entry.code, name: entry.name, symbol: nil)
            let name = entry.name.lowercased()
            table[name] = def
            let words = name.split(separator: " ").map(String.init)
            if let last = words.last {
                let pluralLast: String
                if last.hasSuffix("y") {
                    pluralLast = String(last.dropLast()) + "ies"
                } else if last.hasSuffix("s") {
                    pluralLast = last
                } else {
                    pluralLast = last + "s"
                }
                table[(Array(words.dropLast()) + [pluralLast]).joined(separator: " ")] = def
            }
        }
        return table
    }()
}
