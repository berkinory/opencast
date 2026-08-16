// Standalone test for the calculator engine — compiles the *real* Foundation-only engine sources (no copy to sync): swiftc Opencast/Features/Calculator/Engine/*.swift Tools/calc-test.swift -o /tmp/calc-test && /tmp/calc-test

import Foundation

@main
@MainActor
struct CalcTests {
    static var failures = 0
    static var passes = 0

    static func main() {
        currencyFeed()
        // Arithmetic & precedence
        expectDisplay("2+2", "4")
        expectDisplay("5*7", "35")
        expectDisplay("100/4", "25")
        expectDisplay("2^10", "1,024")
        expectDisplay("2**10", "1,024")
        expectDisplay("2^3^2", "512")  // right-associative
        expectDisplay("4(2+3)", "20")
        expectDisplay("(2+3)(2+3)", "25")
        expectDisplay("2pi", "6.283185307")
        expectDisplay("2sqrt(9)", "6")
        expectDisplay("(5+2)*3", "21")
        expectDisplay("5!", "120")
        expectDisplay("3!!", "720")  // (3!)! — chained postfix
        expectDisplay("-5+3", "-2")
        expectDisplay("-2^2", "-4")  // unary minus binds looser than ^
        expectDisplay("10/4", "2.5")
        expectDisplay("1/3", "0.3333333333")
        expectDisplay("1e6", "1,000,000")
        expectDisplay("1e6 + 1", "1,000,001")
        expectDisplay("1.5e-3 * 2", "0.003")
        expectDisplay("2.5E8 / 2", "125,000,000")
        expectDisplay("2.5 * 4", "10")
        expectDisplay("1,000 + 234", "1,234")  // grouping commas accepted in input

        // Functions
        expectDisplay("sqrt(64)", "8")
        expectDisplay("sqrt 64", "8")
        expectDisplay("sqrt 64 + 36", "44")  // bare arg is one operand: sqrt(64) + 36
        expectDisplay("log(1000)", "3")
        expectDisplay("ln(e)", "1")
        expectDisplay("sin(30deg)", "0.5")
        expectDisplay("cos(60deg)", "0.5")
        expectDisplay("tan(45deg)", "1")
        expectDisplay("sin(pi/2)", "1")
        expectDisplay("abs(-4)", "4")
        expectDisplay("floor(2.7)", "2")
        expectDisplay("ceil(2.1)", "3")
        expectDisplay("round(2.5)", "3")
        expectDisplay("SQRT(64)", "8")  // case-insensitive

        // Constants
        expectDisplay("2*pi", "6.283185307")
        expectDisplay("π*2", "6.283185307")
        expectDisplay("e^2", "7.389056099")

        // Percent
        expectDisplay("20% of 450", "90")
        expectDisplay("%15 of 40", "6")
        expectDisplay("450 + 20%", "540")
        expectDisplay("450 - 15%", "382.5")
        expectDisplay("20%", "0.2")
        expectDisplay("10 % 3", "1")
        expectDisplay("17 mod 5", "2")
        expectDisplay("2 + 10 % 3", "3")

        // Unit conversion — length / weight / temperature / time / area / volume / storage
        expectDisplay("10km to mi", "6.213711922 mi")
        expectDisplay("1 nautical mile to km", "1.852 km")
        expectDisplay("145 mins to timespan", "2 hrs 25 mins")
        expectDisplay("20 days in wk", "2.857142857 week")
        expectDisplay("20 days in weeks", "2.857142857 week")
        expectExpression("20 day in wk", "20 day in wk")
        expectExpression("20 days in weeks", "20 days in weeks")
        expectDisplay("10 km in miles", "6.213711922 mi")
        expectDisplay("5ft in cm", "152.4 cm")
        expectDisplay("1 m to ft", "3.280839895 ft")
        expectDisplay("10 cm in in", "3.937007874 in")
        expectDisplay("10 in in cm", "25.4 cm")  // first "in" is the unit, second the connector
        expectDisplay("16 oz to lb", "1 lb")
        expectDisplay("2.2 lbs to kg", "0.997903214 kg")
        expectDisplay("100 C to F", "212 °F")
        expectDisplay("32F to C", "0 °C")
        expectDisplay("273.15K to C", "0 °C")
        expectDisplay("0 F to C", "-17.77777778 °C")
        expectDisplay("300 K to C", "26.85 °C")
        expectDisplay("90min to hr", "1.5 hr")
        expectDisplay("2hr to min", "120 min")
        expectDisplay("1day to sec", "86,400 s")
        expectDisplay("1 week to hr", "168 hr")
        expectDisplay("2 acre to m2", "8,093.712845 m²")
        expectDisplay("1 m² to ft²", "10.76391042 ft²")
        expectDisplay("2L -> mL", "2,000 mL")
        expectDisplay("1 cup to tbsp", "16 tbsp")
        expectDisplay("1 gal to L", "3.785411784 L")
        expectDisplay("1 GiB to MB", "1,073.741824 MB")
        expectDisplay("1 GB to MiB", "953.6743164 MiB")
        expectDisplay("8 bit to byte", "1 B")
        expectDisplay("2*5 km to mi", "6.213711922 mi")  // expression on the left side

        // Natural-language math
        expectDisplay("square root of 625", "25")
        expectDisplay("2 power 10", "1,024")
        expectDisplay("2 to power 10", "1,024")

        // Number bases
        expectDisplay("255 to hex", "0xFF")
        expectDisplay("255 to binary", "0b11111111")
        expectDisplay("0xff to decimal", "255")
        expectDisplay("0b1010 to decimal", "10")
        expectDisplay("255 to octal", "0o377")
        expectDisplay("0xff", "255")  // bare radix literal echoes decimal

        // Unsupported conversions stay out of the calculator results.
        expectNil("10kg to sec")
        expectNil("100 mL to km")
        expectNil("1 GB to hr")

        // Non-calculator input → no card
        expectNil("safari")
        expectNil("1password")
        expectNil("45")
        expectNil("3.14")
        expectNil("pi")
        expectNil("e")
        expectNil("10km to")  // half-typed conversion
        expectNil("10 to mi")
        expectNil("45+")  // half-typed expression
        expectNil("10em")
        expectNil("sqrt()")
        expectNil("2.5!")  // factorial needs an integer
        expectNil("")

        // Formatting: display grouped, copyText plain
        expectDisplay("1234567*1", "1,234,567")
        expectDisplay("2^50", "1,125,899,906,842,624")
        expectCopy("2^50", "1125899906842624")
        expectDisplay("999999999999999 + 1", "1,000,000,000,000,000")
        expectDisplay("123456789 * 123456789", "1.524157875E+16")
        expectCopy("1234567*1", "1234567")
        expectCopy("10km to mi", "6.213711922 mi")
        expectDisplay("-1234.5-0.25", "-1,234.75")

        // Card expression echo
        expectExpression("3*3", "3×3")
        expectExpression("10km to mi", "10km to mi")

        // Badges on explicit conversions
        expectBadges("10km to mi", source: "Kilometers", target: "Miles")
        expectBadges("100 C to F", source: "Celsius", target: "Fahrenheit")

        // Bare-unit auto-conversion (no connector)
        expectDisplay("1m", "3 feet 3.37007874 inches")
        expectExpression("1m", "1 m")
        expectBadges("1m", source: "Meters", target: "Feet")
        expectDisplay("1hr", "60 min")
        expectBadges("1hr", source: "Hours", target: "Minutes")
        expectDisplay("5ft", "1.524 m")
        expectDisplay("100g", "3.527396195 oz")
        expectDisplay("2*3 kg", "13.22773573 lb")  // value side is a full expression
        expectDisplay("20 celsius", "68 °F")
        expectDisplay("50cm", "19.68503937 in")
        // Ambiguous single-letter aliases stay app searches, not bare temperatures
        expectNil("5k")
        expectNil("100 c")
        expectNil("32f")

        // Date/time — evaluated against a fixed clock: Fri 2026-07-24 00:18 UTC
        expectDisplayAt("hrs till 9am", "8.7 hours")
        expectBadgesAt("hrs till 9am", source: "12:18 AM", target: "9:00 AM")
        expectDisplayAt("hrs till july", "8,207.7 hours")
        expectBadgesAt("hrs till july", source: "12:18 AM", target: "12:00 AM")
        expectDisplayAt("days till 9april", "259 days")
        expectDisplayAt("days until 27 feb", "218 days")
        expectDisplayAt("day until february 27", "218 days")
        expectDisplayAt("years since feb 17 2005", "21 years")
        expectDisplayAt("years since february 17, 2005", "21 years")
        expectDisplayAt("months until feb 27", "7 months")
        expectBadgesAt(
            "days till 9april", source: "Friday, 24 July", target: "Friday, 9 April, 2027")
        expectDisplayAt("days till july", "342 days")
        expectBadgesAt(
            "days till july", source: "Friday, 24 July", target: "Thursday, 1 July, 2027")
        expectDisplayAt("days until tomorrow", "1 day")
        expectDisplayAt("weeks till 9april", "37 weeks")  // 259 / 7
        expectDisplayAt("today + 3 weeks", "Friday, 14 August")
        expectDisplayAt("august 5 + 5", "Monday, 10 August")
        expectDisplayAt("now + 90 min", "Friday, 24 July at 1:48 AM")
        expectDisplayAt("35 days ago", "Friday, 19 June")
        expectDisplayAt("in 5 months", "Thursday, 24 December")
        expectDisplayAt("3 days from now", "Monday, 27 July")
        expectDisplayAt("2 days later", "Sunday, 26 July")
        expectDisplayAt("2 days after monday", "Wednesday, 29 July")
        expectDisplayAt("2 days before monday", "Saturday, 25 July")
        expectDisplayAt("2 days after june 3", "Saturday, 5 June, 2027")
        expectDisplayAt("monday in 3 weeks", "Monday, 17 August")
        expectDisplayAt("time in tokyo", "9:18 AM")
        expectDisplayAt("5pm ldn in sf", "9:00 AM")
        expectDisplayAt("20:10 in pst", "12:10 PM")
        expectDisplayAt("12 AM in UTC+3", "3:00 AM")
        expectNilAt("4pm in utc+")  // incomplete fixed-offset zone must not crash while typing
        expectDisplayAt("time diff Paris", "2 hours")
        expectDisplayAt("4 hours from now", "Friday, 24 July at 4:18 AM")
        expectDisplayAt("jul 4 - today", "345 days")
        expectBadgesAt("jul 4 - today", source: "Sunday, 4 July, 2027", target: "Friday, 24 July")
        // Arithmetic with spaced operators must still be plain math, not date math
        expectDisplayAt("10 - 3", "7")
        expectDisplayAt("450 + 20%", "540")
        // Letter-free `m/d - m/d` is fraction math, not a date difference (both operands are valid arithmetic)
        expectDisplayAt("5/2 - 1/2", "2")
        expectDisplayAt("3/4 - 1/4", "0.5")
        expectDisplayAt("1/2 - 1/4", "0.25")
        // A slash date still reads as a date when the other side names a keyword
        expectDisplayAt("9/4 - today", "42 days")
        expectDisplayAt("today - 9/4", "-42 days")
        // Bare date/unit words alone are app searches, not cards
        expectNilAt("today")
        expectNilAt("july")
        expectNilAt("tomorrow")

        // Angle units (deg is a real unit now, not just a trig postfix)
        expectDisplay("1 deg", "0.01745329252 rad")
        expectExpression("1 deg", "1 deg")
        expectBadges("1 deg", source: "Degrees", target: "Radians")
        expectDisplay("90 deg to rad", "1.570796327 rad")
        expectDisplay("1 rad to deg", "57.29577951 deg")
        expectDisplay("1 turn to deg", "360 deg")
        expectDisplay("200 grad to deg", "180 deg")
        expectDisplay("sin(30deg)", "0.5")  // trig postfix still works inside parens

        // Implied quantity of 1 for number-less conversions
        expectDisplay("day to s", "86,400 s")
        expectDisplay("deg to rad", "0.01745329252 rad")
        expectDisplay("m to ft", "3.280839895 ft")

        // `unit unit` shorthand → 1 of the first in the second
        expectDisplay("day s", "86,400 s")
        expectBadges("day s", source: "Days", target: "Seconds")
        expectDisplay("days s", "86,400 s")
        expectDisplay("hr min", "60 min")
        expectNil("m s")  // different categories → no card, no error

        // Extra unit categories: speed / pressure / data rate
        expectDisplay("100 kmh to mph", "62.13711922 mph")
        expectDisplay("60 mph to kmh", "96.56064 km/h")
        expectDisplay("100 mbps to kbps", "100,000 Kbps")
        expectBadges("100 kmh to mph", source: "Kilometers per Hour", target: "Miles per Hour")

        // Bare-unit auto-conversion coverage for pressure and data-rate neighbors.
        expectDisplay("5 mbar", "0.07251886887 psi")
        expectDisplay("5 kPa", "0.7251886887 psi")
        expectDisplay("5 hPa", "0.07251886887 psi")
        expectDisplay("5 mmHg", "0.0966838873 psi")
        expectDisplay("5 Torr", "0.09668387352 psi")
        expectDisplay("100 bps", "0.1 Kbps")
        expectDisplay("1 Tbps", "1,000 Gbps")
        expectDisplay("2*128 to hex", "0x100")
        expectDisplay("10*5 to hex", "0x32")

        // Percentage phrasings
        expectDisplay("20% off 500", "400")
        expectDisplay("50 as % of 200", "25%")

        // Badges on paths that previously had none
        expectBadges("255 to hex", source: "Decimal", target: "Hexadecimal")
        expectBadges("0xff to decimal", source: "Hexadecimal", target: "Decimal")
        expectBadges("3*3", source: "Expression", target: "Result")
        expectBadges("20% off 500", source: "Expression", target: "Result")

        // days since — past elapsed, against the fixed clock (Fri 2026-07-24)
        expectDisplayAt("days since 9jul", "15 days")
        expectBadgesAt("days since 9jul", source: "Thursday, 9 July", target: "Friday, 24 July")
        expectDisplayAt("weeks since 3jul", "3 weeks")
        expectDisplayAt("days since yesterday", "1 day")
        // Date ± duration now carries the resolved start as a source badge
        expectBadgesAt("today + 3 weeks", source: "Friday, 24 July", target: "Result")

        // Currency — against the fixed `fx` table below (1 USD = 0.92 EUR = 0.79 GBP = 157 JPY)
        expectDisplay("1 euro to dollars", "$1.09")
        expectDisplay("20 usd", "$20.00")
        expectDisplay("20 euro", "$21.74")
        expectDisplay("€20", "$21.74")
        expectExpression("20 usd", "20 usd")
        expectExpression("1 euro to dollars", "1 euro to dollars")
        expectBadges("1 euro to dollars", source: "Euro", target: "US Dollar")
        expectDisplay("50 GBP in euros", "€58.23")
        expectDisplay("2 US dollars to British pounds", "£1.58")
        expectDisplay("100 dollars to yen", "¥15,700.00")
        expectDisplay("100 usd -> eur", "€92.00")
        expectDisplay("2*50 usd to eur", "€92.00")  // expression on the value side
        expectDisplay("$10 + 5€", "€14.20")
        expectExpression("$10 + 5€", "$10 + 5€")
        expectDisplay("10 kg + 500g in pound", "23.14853753 lb")
        expectExpression("10 kg + 500g in pound", "10 kg + 500g in pound")
        expectDisplay("eur to usd", "$1.09")  // implied amount of 1
        expectCopy("100 dollars to yen", "15700.00 JPY")
        // Currency signs, prefixed and suffixed
        expectDisplay("€20 to GBP", "£17.17")
        expectDisplay("20€ to GBP", "£17.17")
        expectDisplay("£50 in dollars", "$63.29")
        expectDisplay("$100 to yen", "¥15,700.00")
        // Sub-cent cross-rates widen instead of collapsing to 0.00
        expectDisplay("1 jpy to usd", "$0.006369")
        // …and stay in plain notation past 1e-5, where "%g" would flip to "5.539e-05"
        expectDisplay("1 idr to usd", "$0.00005539")
        expectCopy("1 idr to usd", "0.00005539 USD")
        // Currency never steals a query the unit table can answer
        expectDisplay("10 pounds to kilograms", "4.5359237 kg")
        expectDisplay("10 pounds", "4.5359237 kg")
        expectDisplay("10 pounds to euros", "€11.65")
        expectBadges("10 pounds to euros", source: "British Pound", target: "Euro")
        // Currency ↔ unit is not a calculator result.
        expectNil("10 usd to kg")
        expectNil("10 kg to usd")
        expectNil("7 usd in b")
        // A known currency the snapshot doesn't quote, and no snapshot at all
        expectError("5 usd to npr", "No exchange rate for NPR.")
        expectErrorWithoutRates(
            "1 eur to usd", "Exchange rates unavailable — check your connection.")
        expectNil("10 usd to nonsense")
        expectNil("usd")  // a lone code is still an app search
        expectNil("btc")  // a lone code is still an app search
        expectError("1 btc to usd", "No exchange rate for BTC.")
        expectNilWithCryptoDisabled("1 btc to usd")
        // The table is generated from the feed's own currency list, so codes nobody hand-typed still
        // resolve — reaching "no rate" (not "no card") is what proves recognition.
        expectError("5 usd to zmw", "No exchange rate for ZMW.")
        expectError("5 usd to afn", "No exchange rate for AFN.")
        check(
            "CurrencyData sizes", expected: "true",
            got:
                "\(CurrencyData.all.count >= 120 && CurrencyData.signs.count >= 20 && CurrencyData.aliases.count >= 100)"
        )
        // Badges come from CLDR's label, which is shorter than the registry name where it matters
        expectBadges("1 chf to usd", source: "Swiss Franc", target: "US Dollar")
        expectBadges("1 aed to usd", source: "UAE Dirham", target: "US Dollar")
        // Nouns only one currency claims are generated — nobody hand-typed these
        expectError("1 zloty to usd", "No exchange rate for PLN.")
        expectError("1 forint to usd", "No exchange rate for HUF.")
        expectError("1 taka to usd", "No exchange rate for BDT.")
        expectError("1 rand to usd", "No exchange rate for ZAR.")
        expectDisplay("1 euro to dollars", "$1.09")
        // Accented nouns resolve with or without the accent
        expectError("1 krónur to usd", "No exchange rate for ISK.")
        expectError("1 kronur to usd", "No exchange rate for ISK.")
        // Nouns several currencies share are the hand-written part, and they must still win
        expectDisplay("100 dollars to yen", "¥15,700.00")
        expectDisplay("10 pounds to euros", "€11.65")
        expectDisplay("1 franc to usd", "$1.23")
        expectError("1 peso to usd", "No exchange rate for MXN.")
        // `krona` is contested (SEK vs ISK) and deliberately assigned to neither
        expectNil("1 krona to usd")
        // Slang is no longer carried: CLDR has no "quid", and we don't hand-maintain synonyms
        expectNil("50 quid to usd")
        expectNil("100 bucks to eur")
        // The last word of a name isn't always its noun — "Special Drawing Rights" is not a "rights"
        expectNil("1 rights to usd")
        // A result too small to show at all reads as a clean zero, never "-0.00"
        expectDisplay("-0.0000000000001 usd to eur", "€0.00")
        expectDisplay("0 usd to eur", "€0.00")
        expectDisplay("-5 usd to eur", "-€4.60")
        // CUP (Cuban peso) is a generated code that collides with a unit; volume still wins
        expectDisplay("1 cup to ml", "236.5882365 mL")
        expectDisplay("1 cup to tbsp", "16 tbsp")

        // Consent gate: without it the currency path doesn't exist. Not an error card explaining a
        // feature the user never enabled — no card at all, so the query falls through to app search.
        expectNilWithoutConsent("1 euro to dollars")
        expectNilWithoutConsent("20 usd")
        expectNilWithoutConsent("100 dollars to yen")
        expectNilWithoutConsent("50 GBP in euros")
        expectNilWithoutConsent("eur to usd")
        expectNilWithoutConsent("€20 to GBP")
        expectNilWithoutConsent("2*50 usd to cad")
        expectNilWithoutConsent("1 zloty to eur")
        // Even the friendly category error stays silent — it would leak that currency exists.
        expectNilWithoutConsent("10 usd to kg")
        expectNilWithoutConsent("10 kg to usd")
        // Everything that isn't currency is untouched by the gate.
        expectDisplayWithoutConsent("10 pounds to kilograms", "4.5359237 kg")
        expectDisplayWithoutConsent("10 pounds", "4.5359237 kg")
        expectDisplayWithoutConsent("1 cup to ml", "236.5882365 mL")
        expectDisplayWithoutConsent("10km to mi", "6.213711922 mi")
        expectDisplayWithoutConsent("2+2", "4")
        expectDisplayWithoutConsent("255 to hex", "0xFF")
        expectDisplayWithoutConsent("20% off 500", "400")

        print("\n\(passes) passed, \(failures) failed")
        exit(failures == 0 ? 0 : 1)
    }

    static func currencyFeed() {
        let fiat = Data("""
        [{"base":"USD","quote":"EUR","rate":0.92},{"base":"USD","quote":"GBP","rate":0.79}]
        """.utf8)
        let snapshot = try? CurrencyFeed.fiat(data: fiat, fetchedAt: Date(timeIntervalSince1970: 10))
        expect(snapshot?.base == "USD", "fiat feed keeps its base")
        expect(snapshot?.rate(for: "USD") == 1, "fiat feed adds the base rate")
        expect(snapshot?.rate(for: "EUR") == 0.92, "fiat feed decodes quoted rates")

        let crypto = Data("""
        {"bitcoin":{"usd":50000},"ethereum":{"usd":2500}}
        """.utf8)
        let assets = [
            CalcCurrency.CryptoAsset(code: "BTC", name: "Bitcoin", id: "bitcoin", symbol: "₿", aliases: []),
            CalcCurrency.CryptoAsset(code: "ETH", name: "Ethereum", id: "ethereum", symbol: "Ξ", aliases: []),
        ]
        let cryptoRates = try? CurrencyFeed.crypto(data: crypto, assets: assets)
        expect(cryptoRates?["BTC"] == 1.0 / 50_000, "crypto feed inverts USD prices")
        expect(cryptoRates?["ETH"] == 1.0 / 2_500, "crypto feed decodes every requested asset")
    }

    static func expect(_ condition: @autoclosure () -> Bool, _ message: String) {
        if condition() {
            passes += 1
        } else {
            failures += 1
            print("FAIL: \(message)")
        }
    }

    // MARK: - Fixed clock for deterministic date/time tests (Fri 2026-07-24 00:18:00 UTC)

    static let clock: (now: Date, calendar: Calendar) = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        calendar.locale = Locale(identifier: "en_US")
        var components = DateComponents()
        components.year = 2026
        components.month = 7
        components.day = 24
        components.hour = 0
        components.minute = 18
        components.second = 0
        return (calendar.date(from: components)!, calendar)
    }()

    // MARK: - Fixed exchange rates so currency answers are deterministic

    /// NPR, ZMW and AFN are deliberately absent: the table recognizes them (they're in the generated
    /// list), so a query for one must reach "no exchange rate" rather than falling through to no card.
    static let fx = CurrencyRates(
        base: "USD",
        rates: [
            "USD": 1, "EUR": 0.92, "GBP": 0.79, "JPY": 157, "INR": 83.5, "CAD": 1.36,
            "KRW": 1330, "IDR": 18053, "CHF": 0.81, "AED": 3.6725,
        ],
        fetchedAt: Date(timeIntervalSince1970: 1_785_000_000))

    // MARK: - Helpers

    static func expectDisplayAt(_ query: String, _ expected: String) {
        guard
            case .value(let display, _)? = CalcEngine.evaluate(
                query, now: clock.now, calendar: clock.calendar)?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectBadgesAt(_ query: String, source: String, target: String) {
        guard let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar)
        else {
            fail(query, expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(query + " [source badge]", expected: source, got: result.sourceBadge ?? "nil")
        check(query + " [target badge]", expected: target, got: result.targetBadge ?? "nil")
    }

    static func expectNilAt(_ query: String) {
        if let result = CalcEngine.evaluate(query, now: clock.now, calendar: clock.calendar) {
            fail(query, expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    static func expectBadges(_ query: String, source: String, target: String) {
        guard let result = CalcEngine.evaluate(query, currency: .on(fx)) else {
            fail(query, expected: "\(source) → \(target)", got: "nil")
            return
        }
        check(query + " [source badge]", expected: source, got: result.sourceBadge ?? "nil")
        check(query + " [target badge]", expected: target, got: result.targetBadge ?? "nil")
    }

    static func expectDisplay(_ query: String, _ expected: String) {
        guard case .value(let display, _)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectCopy(_ query: String, _ expected: String) {
        guard case .value(_, let copy)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: copy)
    }

    static func expectError(_ query: String, _ expected: String) {
        guard case .error(let message)? = CalcEngine.evaluate(query, currency: .on(fx))?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    /// Consented, but no snapshot has landed yet — first run, or still offline.
    static func expectErrorWithoutRates(_ query: String, _ expected: String) {
        guard case .error(let message)? = CalcEngine.evaluate(query, currency: .on(nil))?.payload
        else {
            fail(query, expected: "error: \(expected)", got: "nil / value")
            return
        }
        check(query, expected: expected, got: message)
    }

    static func expectNilWithCryptoDisabled(_ query: String) {
        if let result = CalcEngine.evaluate(
            query, currency: .onWithCrypto(fx, cryptoEnabled: false)
        ) {
            fail(query, expected: "nil (crypto disabled)", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// No consent: the currency path must not engage. Checks the explicit `.off` source and the
    /// default argument, since a caller that forgets to pass one must still get the feature off.
    static func expectNilWithoutConsent(_ query: String) {
        if let result = CalcEngine.evaluate(query, currency: .off) {
            fail(query, expected: "nil (consent withheld)", got: "\(result.payload)")
        } else if let result = CalcEngine.evaluate(query) {
            fail(query, expected: "nil (default source)", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    /// A non-currency answer that must survive with the feature switched off.
    static func expectDisplayWithoutConsent(_ query: String, _ expected: String) {
        guard case .value(let display, _)? = CalcEngine.evaluate(query, currency: .off)?.payload
        else {
            fail(query, expected: expected, got: "nil / error")
            return
        }
        check(query, expected: expected, got: display)
    }

    static func expectExpression(_ query: String, _ expected: String) {
        guard let result = CalcEngine.evaluate(query, currency: .on(fx)) else {
            fail(query, expected: expected, got: "nil")
            return
        }
        check(query, expected: expected, got: result.expression)
    }

    static func expectNil(_ query: String) {
        if let result = CalcEngine.evaluate(query, currency: .on(fx)) {
            fail(query, expected: "nil", got: "\(result.payload)")
        } else {
            passes += 1
        }
    }

    static func check(_ query: String, expected: String, got: String) {
        if got == expected {
            passes += 1
        } else {
            fail(query, expected: expected, got: got)
        }
    }

    static func fail(_ query: String, expected: String, got: String) {
        failures += 1
        print("FAIL  \(query)\n      expected: \(expected)\n      got:      \(got)")
    }
}
