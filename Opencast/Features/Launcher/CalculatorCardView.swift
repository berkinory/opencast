import SwiftUI

/// One-deep memo over `CalcEngine.evaluate`, mirroring `AppIndex.matchCache`, so hover/selection
/// re-renders with the same query don't re-run the evaluator. Keyed on the consent flag plus the
/// snapshot's `fetchedAt`, so flipping the setting or landing a fresh table invalidates the memo
/// without comparing the rate table itself.
@MainActor
enum CalcMemo {
    private static var cache:
        (
            query: String, enabled: Bool, cryptoEnabled: Bool, stamp: Date?, result: CalcResult?
        )?

    static func evaluate(_ query: String, currency: CurrencySource) -> CalcResult? {
        let enabled = currency.isOn
        let cryptoEnabled = currency.cryptoEnabled
        let stamp = currency.rates?.fetchedAt
        if let cache,
            cache.query == query,
            cache.enabled == enabled,
            cache.cryptoEnabled == cryptoEnabled,
            cache.stamp == stamp
        {
            return cache.result
        }
        var calendar = Calendar.current
        calendar.locale = Locale.current
        let result = CalcEngine.evaluate(query, now: Date(), calendar: calendar, currency: currency)
        let visibleResult = result?.isActionable == true ? result : nil
        cache = (query, enabled, cryptoEnabled, stamp, visibleResult)
        return visibleResult
    }
}

/// The inline answer card pinned above the app results (expression → result, or a friendly message on impossible conversion); selectable like a row, Enter copies.
struct CalculatorCard: View {
    let result: CalcResult
    let selected: Bool
    @State private var hovered = false

    private var fill: Color {
        if selected { return Theme.Colors.selection }
        if hovered { return Theme.Colors.rowHover }
        return .clear
    }

    var body: some View {
        Group {
            switch result.payload {
            case .value(let display, _):
                HStack(spacing: 0) {
                    CalcColumn(badge: result.sourceBadge, weight: .semibold) {
                        CalcExpression(text: result.expression)
                    }
                    Color.clear
                        .frame(width: Theme.Spacing.xxl)
                    CalcColumn(badge: result.targetBadge, weight: .bold) {
                        Text(display)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            case .error(let message):
                HStack(spacing: Theme.Spacing.md) {
                    Image(systemName: "exclamationmark.triangle")
                        .symbolRenderingMode(.hierarchical)
                    Text(message)
                        .lineLimit(1)
                }
                .font(Theme.Typography.body)
                .foregroundStyle(Theme.Colors.textSecondary)
                .frame(maxWidth: .infinity)
            }
        }
        .padding(.horizontal, Theme.Spacing.xl)
        .padding(.vertical, Theme.Spacing.xl)
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(Theme.Colors.cardFill)
        )
        .background(
            RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous)
                .fill(fill)
        )
        .armedHover($hovered)
        .overlay {
            if case .value = result.payload {
                CalcArrowDivider()
            }
        }
    }
}

/// One side of the two-column answer card: the value line with an optional word-name badge near the card's lower edge.
private struct CalcColumn<Content: View>: View {
    let badge: String?
    let weight: Font.Weight
    let content: Content

    init(badge: String?, weight: Font.Weight, @ViewBuilder content: () -> Content) {
        self.badge = badge
        self.weight = weight
        self.content = content()
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                content
                    .font(Theme.Typography.calcResult.weight(weight))
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .frame(maxHeight: .infinity)
            if let badge {
                Text(badge)
                    .font(Theme.Typography.calcBadge)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .foregroundStyle(Theme.Colors.textPrimary)
                    .padding(.horizontal, Theme.Spacing.md)
                    .padding(.vertical, Theme.Spacing.xs)
                    .background(
                        RoundedRectangle(cornerRadius: Theme.Radius.keyCap, style: .continuous)
                            .fill(Theme.Colors.controlSurface)
                    )
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.Size.calcCardColumnHeight)
        .padding(.horizontal, Theme.Spacing.md)
    }
}

private struct CalcArrowDivider: View {
    var body: some View {
        VStack(spacing: 0) {
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)
            Spacer(minLength: 0)
            Image(systemName: "arrow.right")
                .font(Theme.Typography.calcArrow)
                .foregroundStyle(Theme.Colors.textPrimary)
                .padding(.vertical, Theme.Spacing.lg)
            Spacer(minLength: 0)
            Rectangle()
                .fill(Theme.Colors.separator)
                .frame(width: 1)
        }
        .frame(width: Theme.Spacing.xxl)
        .frame(maxHeight: .infinity)
    }
}

private struct CalcExpression: View {
    let text: String

    var body: some View {
        styledText
    }

    private var styledText: Text {
        let pattern = #"\b(to|in|until|till|til|since|from|ago|of|off|as|at|on|between)\b|[+−×÷^*/%]"#
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else {
            return Text(text)
        }

        var output = Text("")
        var cursor = text.startIndex
        let range = NSRange(location: 0, length: text.utf16.count)
        for match in regex.matches(in: text, range: range) {
            guard let matchRange = Range(match.range, in: text) else { continue }
            let matchedText = String(text[matchRange])
            let isLeadingPercent =
                matchedText == "%"
                && text[..<matchRange.lowerBound].trimmingCharacters(in: .whitespaces).isEmpty
            guard !isLeadingPercent else { continue }
            if matchedText.caseInsensitiveCompare("in") == .orderedSame,
                !isConversionConnector(text, at: matchRange)
            {
                continue
            }
            output = Text("\(output)\(Text(text[cursor..<matchRange.lowerBound]))")
            output = Text("\(output)\(Text(text[matchRange]).foregroundStyle(Theme.Colors.textTertiary))")
            cursor = matchRange.upperBound
        }
        return Text("\(output)\(Text(text[cursor...]))")
    }

    private func isConversionConnector(_ text: String, at range: Range<String.Index>) -> Bool {
        let before = String(text[..<range.lowerBound])
        let after = String(text[range.upperBound...])
        guard !after.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
        if let afterTokens = CalcTokenizer.tokenize(after),
            case .ident("to")? = afterTokens.first
        {
            return false
        }
        if let beforeTokens = CalcTokenizer.tokenize(before),
            let afterTokens = CalcTokenizer.tokenize(after),
            !afterTokens.isEmpty,
            CalcUnits.parseConversion(beforeTokens + [.arrow] + afterTokens) != nil
        {
            return true
        }
        if let beforeTokens = CalcTokenizer.tokenize(before),
            case .number? = beforeTokens.last
        {
            return false
        }
        return true
    }
}

/// Actions menu content for the calculator card — only answers can be copied, so an error card gets no menu (the caller passes `calc` only for value payloads).
@MainActor
enum CalcActionsMenu {
    static func content(result: CalcResult, coordinator: CalculatorCoordinator) -> PopoverMenuContent {
        PopoverMenuContent(
            header: result.expression,
            items: [
                PopoverMenuItem(title: "Copy Answer", systemImage: "doc.on.doc", shortcut: "↵") {
                    coordinator.copy(result)
                }
            ]
        )
    }
}
