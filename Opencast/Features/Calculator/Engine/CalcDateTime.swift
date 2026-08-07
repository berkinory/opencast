import Foundation

/// Natural-language date/time calculations for the launcher card, kept Foundation-only so `Tools/calc-test.swift` compiles it standalone. `now`/`calendar` are injected so the tests can assert exact strings against a fixed clock. Supported forms include durations until/since a moment, calendar months/years, relative dates (`35 days ago`, `2 days later`, `2 days after monday`, `monday in 3 weeks`), date arithmetic, and differences between moments.
enum CalcDateTime {
    /// Which occurrence of a bare, recurring date/time a phrase resolves to: the upcoming one (`till`) or the most recent past one (`since`). Absolute dates ignore it.
    private enum MomentBias { case future, past }

    static func evaluate(_ raw: String, now: Date = Date(), calendar: Calendar = .current)
        -> CalcResult?
    {
        let echo = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        let query = echo.lowercased()
        guard !query.isEmpty else { return nil }

        // Cheap gate: our grammars always carry a connector, so app searches skip all the parsing.
        let hasUntil =
            query.contains(" till ") || query.contains(" until ") || query.contains(" til ")
        let hasSince = query.contains(" since ")
        let hasAgo = query.hasSuffix(" ago")
        let hasIn = query.hasPrefix("in ") || query.contains(" in ") || query.contains(" from now")
        let hasTimeZone = query.hasPrefix("time in ") || query.hasPrefix("time diff ") || query.contains(" in ")
        let hasArith = query.contains(" + ") || query.contains(" - ")
        let hasRelative =
            query.hasSuffix(" later") || query.contains(" after ") || query.contains(" before ")
        guard hasUntil || hasSince || hasAgo || hasTimeZone || hasIn || hasArith || hasRelative
        else { return nil }

        if hasUntil, let result = parseUntil(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasSince, let result = parseSince(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasAgo, let result = parseAgo(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasTimeZone, let result = parseTimeZone(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasIn, let result = parseIn(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasRelative, let result = parseRelative(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        if hasArith, let result = parseArithmetic(query, echo: echo, now: now, calendar: calendar) {
            return result
        }
        return nil
    }

    // MARK: - Grammar A: duration until a moment

    private static func parseUntil(_ query: String, echo: String, now: Date, calendar: Calendar)
        -> CalcResult?
    {
        guard let connector = [" until ", " till ", " til "].first(where: query.contains) else {
            return nil
        }
        let parts = query.components(separatedBy: connector)
        guard parts.count == 2,
            let unit = durationUnit(parts[0]),
            let moment = parseMoment(parts[1], now: now, calendar: calendar)
        else { return nil }

        let reference = unit.subDay ? now : calendar.startOfDay(for: now)
        let target = unit.subDay ? moment.date : calendar.startOfDay(for: moment.date)

        let value: Double
        switch unit.kind {
        case .day:
            value = Double(calendar.dateComponents([.day], from: reference, to: target).day ?? 0)
        case .week:
            let days = calendar.dateComponents([.day], from: reference, to: target).day ?? 0
            value = Double(days) / 7
        case .month:
            value = Double(calendar.dateComponents([.month], from: reference, to: target).month ?? 0)
        case .year:
            value = Double(calendar.dateComponents([.year], from: reference, to: target).year ?? 0)
        case .subSecond:
            value = target.timeIntervalSince(reference) / unit.seconds
        }

        let word = value == 1 ? unit.singular : unit.plural
        let locale = calendar.locale ?? Locale.current
        let source =
            unit.subDay
            ? timeString(now, calendar: calendar)
            : dateString(reference, now: now, calendar: calendar)
        let targetBadge =
            unit.subDay
            ? timeString(moment.date, calendar: calendar)
            : dateString(target, now: now, calendar: calendar)

        return CalcResult(
            expression: echo,
            sourceBadge: source,
            targetBadge: targetBadge,
            payload: .value(
                display: "\(CalcFormatter.display(value, locale: locale)) \(word)",
                copyText: "\(CalcFormatter.copyText(value)) \(word)"))
    }

    // MARK: - Grammar B: duration since a past moment

    private static func parseSince(_ query: String, echo: String, now: Date, calendar: Calendar)
        -> CalcResult?
    {
        let parts = query.components(separatedBy: " since ")
        guard parts.count == 2,
            let unit = durationUnit(parts[0]),
            let moment = parseMoment(parts[1], now: now, calendar: calendar, bias: .past)
        else { return nil }

        let reference = unit.subDay ? now : calendar.startOfDay(for: now)
        let past = unit.subDay ? moment.date : calendar.startOfDay(for: moment.date)

        let value: Double
        switch unit.kind {
        case .day:
            value = Double(calendar.dateComponents([.day], from: past, to: reference).day ?? 0)
        case .week:
            let days = calendar.dateComponents([.day], from: past, to: reference).day ?? 0
            value = Double(days) / 7
        case .month:
            value = Double(calendar.dateComponents([.month], from: past, to: reference).month ?? 0)
        case .year:
            value = Double(calendar.dateComponents([.year], from: past, to: reference).year ?? 0)
        case .subSecond:
            value = reference.timeIntervalSince(past) / unit.seconds
        }

        let word = value == 1 ? unit.singular : unit.plural
        let locale = calendar.locale ?? Locale.current
        let source =
            unit.subDay
            ? timeString(past, calendar: calendar)
            : dateString(past, now: now, calendar: calendar)
        let targetBadge =
            unit.subDay
            ? timeString(now, calendar: calendar)
            : dateString(reference, now: now, calendar: calendar)

        return CalcResult(
            expression: echo,
            sourceBadge: source,
            targetBadge: targetBadge,
            payload: .value(
                display: "\(CalcFormatter.display(value, locale: locale)) \(word)",
                copyText: "\(CalcFormatter.copyText(value)) \(word)"))
    }

    // MARK: - Grammar C: elapsed date as a calendar value

    private static func parseAgo(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let phrase = String(query.dropLast(" ago".count))
        guard let duration = parseDurationPhrase(phrase),
            let date = calendar.date(byAdding: duration.component, value: -duration.count, to: now)
        else { return nil }
        let display = momentString(date, hasTime: duration.subDay, now: now, calendar: calendar)
        return CalcResult(
            expression: echo, sourceBadge: "Now", targetBadge: "Result",
            payload: .value(display: display, copyText: display))
    }

    // MARK: - Time zones

    private static func parseTimeZone(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        if query.hasPrefix("time diff ") {
            let name = String(query.dropFirst("time diff ".count))
            guard let zone = timeZone(named: name) else { return nil }
            let currentOffset = calendar.timeZone.secondsFromGMT(for: now)
            let targetOffset = zone.secondsFromGMT(for: now)
            let difference = Double(targetOffset - currentOffset) / 3600
            let locale = calendar.locale ?? Locale.current
            let display = "\(CalcFormatter.display(difference, locale: locale)) hours"
            return CalcResult(
                expression: echo, sourceBadge: calendar.timeZone.identifier,
                targetBadge: zone.identifier,
                payload: .value(display: display, copyText: display))
        }

        guard let connector = query.range(of: " in ") else { return nil }
        let left = String(query[..<connector.lowerBound])
        let targetName = String(query[connector.upperBound...])
        guard let targetZone = timeZone(named: targetName) else { return nil }
        let targetCalendar = calendarFor(targetZone, base: calendar)

        let sourceCalendar: Calendar
        let sourceMoment: Moment
        if left == "time" {
            sourceCalendar = calendar
            sourceMoment = Moment(date: now, hasTime: true)
        } else {
            let atoms = left.split(whereSeparator: \.isWhitespace).map(String.init)
            if let parsedZone = atoms.last.flatMap(timeZone(named:)), atoms.count >= 2 {
                let timePhrase = atoms.dropLast().joined(separator: " ")
                sourceCalendar = calendarFor(parsedZone, base: calendar)
                guard
                    let parsed = clockMomentOnDate(
                        timePhrase, now: now, calendar: sourceCalendar)
                else { return nil }
                sourceMoment = parsed
            } else {
                sourceCalendar = calendar
                guard let parsed = clockMomentOnDate(left, now: now, calendar: sourceCalendar)
                else { return nil }
                sourceMoment = parsed
            }
        }

        let display = timeString(sourceMoment.date, calendar: targetCalendar)
        return CalcResult(
            expression: echo,
            sourceBadge: timeString(sourceMoment.date, calendar: sourceCalendar),
            targetBadge: targetZone.identifier,
            payload: .value(display: display, copyText: display))
    }

    private static func timeZone(named name: String) -> TimeZone? {
        let normalized = name.trimmingCharacters(in: .whitespaces).lowercased()
        if let identifier = timeZoneIdentifiers[normalized] {
            return TimeZone(identifier: identifier)
        }
        if normalized == "utc" || normalized == "gmt" {
            return TimeZone(secondsFromGMT: 0)
        }
        if normalized.hasPrefix("utc") || normalized.hasPrefix("gmt") {
            return fixedOffsetTimeZone(String(normalized.dropFirst(3)))
        }
        return TimeZone(identifier: name.trimmingCharacters(in: .whitespaces))
    }

    private static func fixedOffsetTimeZone(_ text: String) -> TimeZone? {
        guard let sign = text.first, sign == "+" || sign == "-" else { return nil }
        let components = text.dropFirst().split(separator: ":")
        guard components.count <= 2, !components.isEmpty,
            let hours = Int(components[0]), (0...23).contains(hours)
        else { return nil }
        let minutes = components.count == 2 ? Int(components[1]) ?? -1 : 0
        guard (0...59).contains(minutes) else { return nil }
        let seconds = (hours * 3600 + minutes * 60) * (sign == "+" ? 1 : -1)
        return TimeZone(secondsFromGMT: seconds)
    }

    private static func clockMomentOnDate(
        _ phrase: String, now: Date, calendar: Calendar
    ) -> Moment? {
        let atoms = atomize(phrase)
        let clock: (hour: Int, minute: Int)?
        if atoms.count == 1 {
            clock = parseClock(atoms[0])
        } else if atoms.count == 2, atoms[1] == "am" || atoms[1] == "pm",
            let parsed = parseClock(atoms[0]), (1...12).contains(parsed.hour)
        {
            let hour = atoms[1] == "pm" ? (parsed.hour % 12) + 12 : parsed.hour % 12
            clock = (hour, parsed.minute)
        } else {
            clock = nil
        }
        guard let clock,
            let date = calendar.date(
                bySettingHour: clock.hour, minute: clock.minute, second: 0,
                of: calendar.startOfDay(for: now))
        else { return nil }
        return Moment(date: date, hasTime: true)
    }

    private static func calendarFor(_ timeZone: TimeZone, base: Calendar) -> Calendar {
        var calendar = base
        calendar.timeZone = timeZone
        return calendar
    }

    // MARK: - Grammar D: future date offsets

    private static func parseIn(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let base: Moment
        let durationPhrase: String
        let baseIsImplicitNow: Bool
        if query.hasPrefix("in ") {
            base = Moment(date: now, hasTime: true)
            baseIsImplicitNow = true
            durationPhrase = String(query.dropFirst(3))
        } else if let range = query.range(of: " from now") {
            guard range.upperBound == query.endIndex else { return nil }
            base = Moment(date: now, hasTime: true)
            baseIsImplicitNow = true
            durationPhrase = String(query[..<range.lowerBound])
        } else {
            guard let connector = query.range(of: " in ") else { return nil }
            let left = String(query[..<connector.lowerBound])
            durationPhrase = String(query[connector.upperBound...])
            guard let parsed = parseMoment(left, now: now, calendar: calendar) else { return nil }
            base = parsed
            baseIsImplicitNow = false
        }

        guard let duration = parseDurationPhrase(durationPhrase),
            let result = calendar.date(
                byAdding: duration.component, value: duration.count, to: base.date)
        else { return nil }
        let display = momentString(
            result, hasTime: (!baseIsImplicitNow && base.hasTime) || duration.subDay, now: now, calendar: calendar)
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(
                base.date, hasTime: base.hasTime, now: now, calendar: calendar),
            targetBadge: "Result", payload: .value(display: display, copyText: display))
    }

    // MARK: - Grammar E: relative date offsets

    private static func parseRelative(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        let base: Moment
        let baseIsImplicitNow: Bool
        let durationPhrase: String
        let sign: Int

        if query.hasSuffix(" later") {
            base = Moment(date: now, hasTime: true)
            baseIsImplicitNow = true
            durationPhrase = String(query.dropLast(" later".count))
            sign = 1
        } else if let range = query.range(of: " after ") {
            durationPhrase = String(query[..<range.lowerBound])
            let basePhrase = String(query[range.upperBound...])
            guard !durationPhrase.isEmpty,
                let parsed = parseMoment(basePhrase, now: now, calendar: calendar)
            else { return nil }
            base = parsed
            baseIsImplicitNow = false
            sign = 1
        } else if let range = query.range(of: " before ") {
            durationPhrase = String(query[..<range.lowerBound])
            let basePhrase = String(query[range.upperBound...])
            guard !durationPhrase.isEmpty,
                let parsed = parseMoment(basePhrase, now: now, calendar: calendar)
            else { return nil }
            base = parsed
            baseIsImplicitNow = false
            sign = -1
        } else {
            return nil
        }

        guard let duration = parseDurationPhrase(durationPhrase),
            sign == 1 || duration.count != .min
        else { return nil }
        let signed = sign == 1 ? duration.count : -duration.count
        guard
            let result = calendar.date(
                byAdding: duration.component, value: signed, to: base.date)
        else { return nil }

        let hasTime = (!baseIsImplicitNow && base.hasTime) || duration.subDay
        return CalcResult(
            expression: echo,
            sourceBadge: momentString(
                base.date, hasTime: base.hasTime, now: now, calendar: calendar),
            targetBadge: "Result",
            payload: .value(
                display: momentString(result, hasTime: hasTime, now: now, calendar: calendar),
                copyText: momentString(result, hasTime: hasTime, now: now, calendar: calendar)))
    }

    // MARK: - Grammars F & G: moment ± duration / moment − moment

    private static func parseArithmetic(
        _ query: String, echo: String, now: Date, calendar: Calendar
    ) -> CalcResult? {
        // Split on the earliest space-surrounded operator; unspaced dashes (ISO dates, times) stay intact.
        let plus = query.range(of: " + ")
        let minus = query.range(of: " - ")
        let (opRange, op): (Range<String.Index>, Character)
        switch (plus, minus) {
        case (let p?, let m?): (opRange, op) = p.lowerBound < m.lowerBound ? (p, "+") : (m, "-")
        case (let p?, nil): (opRange, op) = (p, "+")
        case (nil, let m?): (opRange, op) = (m, "-")
        default: return nil
        }

        let left = String(query[..<opRange.lowerBound])
        let right = String(query[opRange.upperBound...])
        guard let base = parseMoment(left, now: now, calendar: calendar) else { return nil }

        // C: moment ± duration → a new moment.
        if let duration = parseDurationPhrase(right) {
            // Negating Int.min traps; degrade to no card on that edge.
            guard op == "+" || duration.count != .min else { return nil }
            let signed = op == "-" ? -duration.count : duration.count
            guard
                let result = calendar.date(
                    byAdding: duration.component, value: signed, to: base.date)
            else { return nil }
            let hasTime = base.hasTime || duration.subDay
            let display = momentString(result, hasTime: hasTime, now: now, calendar: calendar)
            let sourceBadge = momentString(
                base.date, hasTime: base.hasTime, now: now, calendar: calendar)
            return CalcResult(
                expression: echo, sourceBadge: sourceBadge, targetBadge: "Result",
                payload: .value(display: display, copyText: display))
        }

        // D: moment − moment → a whole-day difference. A real date subtraction always names a month/weekday/keyword; two letter-free operands (`5/2 - 1/2`) are equally valid as arithmetic, so defer to the calculator rather than silently reading them as dates.
        guard op == "-",
            left.contains(where: \.isLetter) || right.contains(where: \.isLetter),
            let other = parseMoment(right, now: now, calendar: calendar)
        else {
            return nil
        }
        let days =
            calendar.dateComponents(
                [.day], from: calendar.startOfDay(for: other.date),
                to: calendar.startOfDay(for: base.date)
            ).day ?? 0
        let word = abs(days) == 1 ? "day" : "days"
        return CalcResult(
            expression: echo,
            sourceBadge: dateString(base.date, now: now, calendar: calendar),
            targetBadge: dateString(other.date, now: now, calendar: calendar),
            payload: .value(display: "\(days) \(word)", copyText: "\(days) \(word)"))
    }

    // MARK: - Moment parsing

    private struct Moment {
        let date: Date
        /// True when the phrase named a clock time ("9am", "now"); false for a bare date, so callers know whether to show a time badge.
        let hasTime: Bool
    }

    private static func parseMoment(
        _ phrase: String, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        let normalized = phrase.replacingOccurrences(
            of: #"(\d+)(st|nd|rd|th)\b"#, with: "$1", options: .regularExpression)
        let atoms = atomize(normalized)
        switch atoms.count {
        case 1:
            return parseSingle(atoms[0], now: now, calendar: calendar, bias: bias)
        case 2:
            return parsePair(atoms[0], atoms[1], now: now, calendar: calendar, bias: bias)
        case 3:
            return parseTriple(atoms[0], atoms[1], atoms[2], now: now, calendar: calendar)
        default:
            return nil
        }
    }

    private static func parseSingle(
        _ atom: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        let sod = calendar.startOfDay(for: now)
        switch atom {
        case "now": return Moment(date: now, hasTime: true)
        case "today": return Moment(date: sod, hasTime: false)
        case "tomorrow":
            return shift(sod, days: 1, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        case "yesterday":
            return shift(sod, days: -1, calendar: calendar).map { Moment(date: $0, hasTime: false) }
        case "noon": return clockMoment(hour: 12, minute: 0, now: now, calendar: calendar, bias: bias)
        case "midnight":
            return clockMoment(hour: 0, minute: 0, now: now, calendar: calendar, bias: bias)
        default: break
        }
        if let weekday = weekdayByName[atom] {
            return nextWeekday(
                weekday, offsetToFuture: false, past: bias == .past, now: now, calendar: calendar)
        }
        if let month = monthByName[atom] {
            return monthDayMoment(month: month, day: 1, now: now, calendar: calendar, bias: bias)
        }
        return parseDateAtom(atom, now: now, calendar: calendar, bias: bias)
    }

    private static func parseTriple(
        _ a: String, _ b: String, _ c: String, now: Date, calendar: Calendar
    ) -> Moment? {
        if let year = Int(c), let day = Int(a), let month = monthByName[b],
            let date = makeDate(fullYear(year), month, day, calendar)
        {
            return Moment(date: date, hasTime: false)
        }
        if let year = Int(c), let month = monthByName[a], let day = Int(b),
            let date = makeDate(fullYear(year), month, day, calendar)
        {
            return Moment(date: date, hasTime: false)
        }
        return nil
    }

    private static func parsePair(
        _ a: String, _ b: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        // number + month  /  month + number  →  a day in that month
        if let month = monthByName[b], let day = Int(a) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        if let month = monthByName[a], let day = Int(b) {
            return monthDayMoment(month: month, day: day, now: now, calendar: calendar, bias: bias)
        }
        // clock + am/pm  →  a time today (or tomorrow if it has passed)
        if b == "am" || b == "pm", let (hour, minute) = parseClock(a) {
            guard (1...12).contains(hour) else { return nil }
            let adjusted = b == "pm" ? (hour % 12) + 12 : hour % 12
            return clockMoment(
                hour: adjusted, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        // next / last  +  weekday or month
        if a == "next" || a == "last" {
            if let weekday = weekdayByName[b] {
                return nextWeekday(
                    weekday, offsetToFuture: a == "next", past: a == "last", now: now,
                    calendar: calendar)
            }
            if let month = monthByName[b] {
                return monthDayMoment(
                    month: month, day: 1, now: now, calendar: calendar,
                    bias: a == "last" ? .past : .future)
            }
        }
        return nil
    }

    /// A lone numeric atom that carries its own separators: `14:00`, `2027-04-09`, `9/4`, `9/4/2027`.
    private static func parseDateAtom(
        _ atom: String, now: Date, calendar: Calendar, bias: MomentBias
    ) -> Moment? {
        if atom.contains(":") {
            guard let (hour, minute) = parseClock(atom) else { return nil }
            return clockMoment(hour: hour, minute: minute, now: now, calendar: calendar, bias: bias)
        }
        if atom.contains("-") {
            let parts = atom.split(separator: "-").map(String.init)
            guard parts.count == 3, let year = Int(parts[0]), year > 31,
                let month = Int(parts[1]), let day = Int(parts[2]),
                let date = makeDate(year, month, day, calendar)
            else { return nil }
            return Moment(date: date, hasTime: false)
        }
        if atom.contains("/") {
            let parts = atom.split(separator: "/").map(String.init)
            if parts.count == 2, let month = Int(parts[0]), let day = Int(parts[1]) {
                return monthDayMoment(
                    month: month, day: day, now: now, calendar: calendar, bias: bias)
            }
            if parts.count == 3, let month = Int(parts[0]), let day = Int(parts[1]),
                let year = Int(parts[2]), let date = makeDate(fullYear(year), month, day, calendar)
            {
                return Moment(date: date, hasTime: false)
            }
        }
        return nil
    }

    // MARK: - Moment builders

    private static func clockMoment(
        hour: Int, minute: Int, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        guard (0...23).contains(hour), (0...59).contains(minute) else { return nil }
        let sod = calendar.startOfDay(for: now)
        guard var date = calendar.date(bySettingHour: hour, minute: minute, second: 0, of: sod)
        else { return nil }
        switch bias {
        case .future:
            if date <= now, let next = shift(date, days: 1, calendar: calendar) { date = next }
        case .past:
            if date > now, let prev = shift(date, days: -1, calendar: calendar) { date = prev }
        }
        return Moment(date: date, hasTime: true)
    }

    /// The given day of `month`: with `.future` bias the upcoming occurrence (this year if still ahead, else next), with `.past` the most recent one (this year if already passed, else last) — matching the "upcoming"/"since" readings of a bare date.
    private static func monthDayMoment(
        month: Int, day: Int, now: Date, calendar: Calendar, bias: MomentBias = .future
    ) -> Moment? {
        let year = calendar.component(.year, from: now)
        guard let thisYear = makeDate(year, month, day, calendar) else { return nil }
        let sod = calendar.startOfDay(for: now)
        switch bias {
        case .future:
            if thisYear >= sod { return Moment(date: thisYear, hasTime: false) }
            guard let nextYear = makeDate(year + 1, month, day, calendar) else { return nil }
            return Moment(date: nextYear, hasTime: false)
        case .past:
            if thisYear <= sod { return Moment(date: thisYear, hasTime: false) }
            guard let lastYear = makeDate(year - 1, month, day, calendar) else { return nil }
            return Moment(date: lastYear, hasTime: false)
        }
    }

    private static func nextWeekday(
        _ weekday: Int, offsetToFuture: Bool, past: Bool = false, now: Date, calendar: Calendar
    ) -> Moment? {
        let sod = calendar.startOfDay(for: now)
        let today = calendar.component(.weekday, from: sod)
        if past {
            var back = (today - weekday + 7) % 7
            if back == 0 { back = 7 }
            return shift(sod, days: -back, calendar: calendar).map {
                Moment(date: $0, hasTime: false)
            }
        }
        var ahead = (weekday - today + 7) % 7
        if ahead == 0 && offsetToFuture { ahead = 7 }
        return shift(sod, days: ahead, calendar: calendar).map { Moment(date: $0, hasTime: false) }
    }

    // MARK: - Durations

    private enum DurKind { case subSecond, day, week, month, year }

    private struct DurUnit {
        let seconds: Double
        let singular: String
        let plural: String
        let kind: DurKind
        var subDay: Bool { kind == .subSecond }
    }

    private static func durationUnit(_ phrase: String) -> DurUnit? {
        guard let last = phrase.split(separator: " ").last.map(String.init) else { return nil }
        switch last {
        case "s", "sec", "secs", "second", "seconds":
            return DurUnit(seconds: 1, singular: "second", plural: "seconds", kind: .subSecond)
        case "min", "mins", "minute", "minutes":
            return DurUnit(seconds: 60, singular: "minute", plural: "minutes", kind: .subSecond)
        case "h", "hr", "hrs", "hour", "hours":
            return DurUnit(seconds: 3600, singular: "hour", plural: "hours", kind: .subSecond)
        case "d", "day", "days":
            return DurUnit(seconds: 86400, singular: "day", plural: "days", kind: .day)
        case "wk", "week", "weeks":
            return DurUnit(seconds: 604800, singular: "week", plural: "weeks", kind: .week)
        case "mo", "mos", "month", "months":
            return DurUnit(seconds: 0, singular: "month", plural: "months", kind: .month)
        case "yr", "yrs", "year", "years":
            return DurUnit(seconds: 0, singular: "year", plural: "years", kind: .year)
        default:
            return nil
        }
    }

    /// `<n> <unit>` for date arithmetic; weeks fold to days so `date(byAdding:)` stays DST-safe.
    private static func parseDurationPhrase(_ phrase: String) -> (
        count: Int, component: Calendar.Component, subDay: Bool
    )? {
        let atoms = atomize(phrase)
        if atoms.count == 1, let count = Int(atoms[0]) {
            return (count, .day, false)
        }
        guard atoms.count == 2, let count = Int(atoms[0]) else { return nil }
        switch atoms[1] {
        case "s", "sec", "secs", "second", "seconds": return (count, .second, true)
        case "min", "mins", "minute", "minutes": return (count, .minute, true)
        case "h", "hr", "hrs", "hour", "hours": return (count, .hour, true)
        case "d", "day", "days": return (count, .day, false)
        case "wk", "week", "weeks":
            // Absurd counts overflow the fold to days; degrade to no card rather than trap.
            let (days, overflow) = count.multipliedReportingOverflow(by: 7)
            return overflow ? nil : (days, .day, false)
        case "mo", "mos", "month", "months": return (count, .month, false)
        case "yr", "yrs", "year", "years": return (count, .year, false)
        default: return nil
        }
    }

    // MARK: - Formatting

    private static func momentString(_ date: Date, hasTime: Bool, now: Date, calendar: Calendar)
        -> String
    {
        let day = dateString(date, now: now, calendar: calendar)
        return hasTime ? "\(day) at \(timeString(date, calendar: calendar))" : day
    }

    private static func dateString(_ date: Date, now: Date, calendar: Calendar) -> String {
        let sameYear =
            calendar.component(.year, from: date) == calendar.component(.year, from: now)
        return format(
            date, calendar: calendar, pattern: sameYear ? "EEEE, d MMMM" : "EEEE, d MMMM, yyyy")
    }

    private static func timeString(_ date: Date, calendar: Calendar) -> String {
        format(date, calendar: calendar, pattern: "h:mm a")
    }

    private static func format(_ date: Date, calendar: Calendar, pattern: String) -> String {
        let formatter = DateFormatter()
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        // Follow the injected calendar's locale so weekday/month names match the user's language; the test clock pins en_US for deterministic assertions.
        formatter.locale = calendar.locale ?? Locale(identifier: "en_US")
        formatter.dateFormat = pattern
        return formatter.string(from: date)
    }

    // MARK: - Low-level helpers

    /// Split into letter-runs and number-runs (":", "/", "-", "." stay inside a number-run), so `9april` → ["9","april"] and `2027-04-09` stays whole.
    private static func atomize(_ text: String) -> [String] {
        var atoms: [String] = []
        var current = ""
        var currentIsNumber = false
        func flush() {
            if !current.isEmpty { atoms.append(current) }
            current = ""
        }
        for ch in text {
            if ch == " " || ch == "," {
                flush()
                continue
            }
            let isNumeric = ch.isNumber || ch == ":" || ch == "/" || ch == "-" || ch == "."
            let isLetter = ch.isLetter
            if current.isEmpty {
                current.append(ch)
                currentIsNumber = isNumeric && !isLetter
            } else if isLetter && currentIsNumber {
                flush()
                current.append(ch)
                currentIsNumber = false
            } else if isNumeric && !isLetter && !currentIsNumber {
                flush()
                current.append(ch)
                currentIsNumber = true
            } else {
                current.append(ch)
            }
        }
        flush()
        return atoms
    }

    private static func parseClock(_ atom: String) -> (hour: Int, minute: Int)? {
        if atom.contains(":") {
            let parts = atom.split(separator: ":").map(String.init)
            guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]) else {
                return nil
            }
            return (hour, minute)
        }
        guard let hour = Int(atom) else { return nil }
        return (hour, 0)
    }

    private static func makeDate(_ year: Int, _ month: Int, _ day: Int, _ calendar: Calendar)
        -> Date?
    {
        guard (1...12).contains(month), (1...31).contains(day) else { return nil }
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        guard let date = calendar.date(from: components),
            calendar.component(.day, from: date) == day,
            calendar.component(.month, from: date) == month
        else { return nil }
        return date
    }

    private static func shift(_ date: Date, days: Int, calendar: Calendar) -> Date? {
        calendar.date(byAdding: .day, value: days, to: date)
    }

    /// Expand a 2-digit year the way most date pickers do (00–68 → 2000s, 69–99 → 1900s); 4-digit years pass through.
    private static func fullYear(_ year: Int) -> Int {
        if year >= 100 { return year }
        return year <= 68 ? 2000 + year : 1900 + year
    }

    private static let timeZoneIdentifiers: [String: String] = [
        "ldn": "Europe/London", "london": "Europe/London",
        "sf": "America/Los_Angeles", "san francisco": "America/Los_Angeles",
        "la": "America/Los_Angeles", "nyc": "America/New_York",
        "pst": "Etc/GMT+8", "pdt": "Etc/GMT+7", "est": "Etc/GMT+5",
        "edt": "Etc/GMT+4", "cst": "Etc/GMT+6", "cdt": "Etc/GMT+5",
        "mst": "Etc/GMT+7", "mdt": "Etc/GMT+6", "cet": "Etc/GMT-1", "cest": "Etc/GMT-2",
        "utc": "UTC", "gmt": "GMT",
        "new york": "America/New_York", "chicago": "America/Chicago",
        "toronto": "America/Toronto", "mexico city": "America/Mexico_City",
        "sao paulo": "America/Sao_Paulo", "são paulo": "America/Sao_Paulo",
        "paris": "Europe/Paris", "berlin": "Europe/Berlin", "istanbul": "Europe/Istanbul",
        "dubai": "Asia/Dubai", "mumbai": "Asia/Kolkata", "delhi": "Asia/Kolkata",
        "singapore": "Asia/Singapore", "beijing": "Asia/Shanghai", "shanghai": "Asia/Shanghai",
        "tokyo": "Asia/Tokyo", "seoul": "Asia/Seoul", "sydney": "Australia/Sydney",
    ]

    private static let monthByName: [String: Int] = [
        "january": 1, "jan": 1, "february": 2, "feb": 2, "march": 3, "mar": 3, "april": 4,
        "apr": 4, "may": 5, "june": 6, "jun": 6, "july": 7, "jul": 7, "august": 8, "aug": 8,
        "september": 9, "sep": 9, "sept": 9, "october": 10, "oct": 10, "november": 11, "nov": 11,
        "december": 12, "dec": 12,
    ]

    /// Gregorian weekday numbers (Sunday = 1).
    private static let weekdayByName: [String: Int] = [
        "sunday": 1, "sun": 1, "monday": 2, "mon": 2, "tuesday": 3, "tue": 3, "tues": 3,
        "wednesday": 4, "wed": 4, "thursday": 5, "thu": 5, "thurs": 5, "friday": 6, "fri": 6,
        "saturday": 7, "sat": 7,
    ]
}
