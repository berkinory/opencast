# Inline calculator

`Features/Calculator/` is a **Foundation-only** engine (no AppKit / SwiftUI imports) fronted by
`CalcMemo`, a one-deep memo mirroring `AppIndex`'s. It must stay Foundation-only because the
`Tools/calc-test.swift` harness compiles the real engine sources — including `CalcDateTime`. It is
also **pure**: the one input it can't compute, the FX rate table, is passed in (see Currency below).

## Evaluation pipeline

`CalcEngine.evaluate` runs:

1. Natural-language date/time and time zones (`days until 27 feb`, `years since feb 17 2005`,
   `35 days ago`, `2 days later`, `2 days after monday`, `monday in 3 weeks`, `time in tokyo`,
   `5pm ldn in sf`)
2. Natural-language math (`square root of 625`, `2 power 10`)
3. Numeric reject
4. Tokenize
5. Typed quantity expressions (`$10 + 5€`, `10 kg + 500g in pound`)
6. Base conversion
7. Timespan conversion (`145 mins to timespan`)
8. Explicit unit conversion (`10km to mi`, `1 nautical mile to km`)
9. **Currency and crypto conversion** (`1 euro to dollars`, `€20 to GBP`, `0.1 btc to usd`)
10. **Bare-unit auto-conversion** (`1m` → feet + inches, `1hr` → 60 min, via
   `CalcUnits.parseBareConversion` + the `autoTargets` map)
11. Plain arithmetic

Date/time depends on the clock, so it takes an injected `now` / `calendar` — the public `evaluate(_:)`
uses the live clock, and `evaluate(_:now:calendar:)` lets `calc-test.swift` assert exact strings
against a fixed clock.

`CalcQuantity` handles arithmetic where operands carry compatible units or currencies. The last typed
unit becomes the result unit: `10 kg + 500g` answers in grams, while `10 kg + 500g in pound` converts
the complete expression to pounds. Currency arithmetic is consent-gated and follows the same rule, so
`$10 + 5€` answers in euros. Simple conversions and bare-unit auto-conversions remain on their existing
paths, preserving their current output behavior.

## Currency

`CalcCurrency` mirrors `CalcUnits`' shape: a lookup table plus a `parseConversion` over the same
`expr from (to|in|->) to` token shape, so `eur to usd` implies an amount of 1 exactly like `m to ft`.
It also resolves generated full names and plurals, so `2 US dollars to British pounds` works. Crypto
supports a curated set of major assets from CoinGecko, including BTC, ETH, SOL, BNB, XRP and ADA. A
leading sign is swapped back into amount-first order, so `€20 to GBP` and `20€ to GBP` parse alike.

The table is **generated except for the judgement calls**. `node Tools/gen-currencies.js` joins two
sources on the ISO code and emits `CurrencyData.generated.swift`:

- **Frankfurter** decides which currencies exist — the same feed the rates come from, so the table
  can never list something the app can't price. 165 codes.
- **CLDR** (`en`) decides what humans call them: display name, currency sign, singular/plural noun.
  Read from the pinned `cldr-json` checkout, not the host's `Intl`, whose output shifts with the
  local ICU version.

Only *unambiguous* CLDR data is emitted — 26 signs and 128 nouns. CLDR itself supplies the sign
tie-break: it writes every dollar but USD as `CA$`/`A$`/`NT$`, so plain `$` is claimed by exactly one
currency. Bare Latin letters CLDR lists as symbols (`P` for BWP, `L` for HNL) are dropped, since a
letter is indistinguishable from a word to the tokenizer. Accented nouns are emitted both as written
and folded, so `krónur` and `kronur` both resolve. The noun itself is the name's last word, which is
only wrong where that word isn't one — `NOT_NOUNS` in the generator drops those ("Special Drawing
Rights" is not a "rights").

What's left hand-written in `CalcCurrency.swift` is one table, `contested`: the nouns several
currencies share, where CLDR correctly refuses to choose and the calculator must. `dollars` is
claimed by 22 currencies, `francs` 10, `pounds` 9, `pesos` 8, `rupees` 6. CLDR says "US dollars" and
"Canadian dollars"; nothing in it says a bare "dollars" is USD. Words that stay genuinely ambiguous
are assigned to nobody — `krona` is both SEK and ISK, so it produces no card. Slang and synonyms
(`quid`, `bucks`, `rmb`) are deliberately *not* carried: they'd be hand-maintained data with no
source of truth.

Order is the whole disambiguation story. Currency runs **after** the unit path, so a query both sides
of which are compatible units stays a measurement: `10 pounds to kg` is weight, `10 pounds to euros`
is money, and `1 cup to ml` stays volume even though `CUP` is the Cuban peso. A currency on one side
and a unit on the other produces the same friendly category error as any other mismatch
(`Cannot convert Currency to Weight.`).

### Consent

Currency conversion is available in the calculator by default, but its online rates remain behind an explicit provider-consent sheet. Crypto conversion is a separate optional setting and defaults off; CoinGecko is never contacted while it is off. Enabling rates names the active providers, the three-hour cadence, and what leaves the machine. Declining keeps rates offline. Any future feature that needs the network should follow the same shape rather than inventing a second one.

The gate is a type, not a boolean sprinkled around: `CalcEngine.evaluate` takes a `CurrencySource`
that is either `.off`, `.on(CurrencyRates?)`, or `.onWithCrypto(CurrencyRates?, cryptoEnabled:)`, and it **defaults to `.off`**, so a caller that
forgets to pass one gets the feature disabled rather than silently enabled. `.off` makes
`CalcCurrency.parseConversion` return nil before it parses anything, so a currency query produces no
card at all — not even the category-mismatch error, which would leak that the feature exists.
`.on(nil)` is the consented-but-not-yet-downloaded state, and that is what earns the "rates
unavailable" message.

`CurrencyRateStore` re-checks consent at every entry point rather than trusting a caller: reading the
cache at init, the `source` the engine is handed, `start()`, each turn of the refresh loop, and twice
around the network call itself — once before the request and once after the `await`, since consent
can be withdrawn while a response is in flight. Disabling conversion or crypto stops future requests and removes disabled crypto rates. Revoking consent cancels the loop, drops the snapshot and deletes the cached file. The provider-consent flag lives on the store, deliberately *not* in `AppSettings`, so settings changes cannot silently grant network access.

For "revoking deletes the rates" to be true there has to be exactly one copy, so the fetch runs on a
private **cacheless** `URLSession` (`.ephemeral`, `urlCache = nil`) rather than `URLSession.shared`.
The provider serves the table `Cache-Control: public, max-age=…`, so the shared session would store a
second copy in the on-disk `URLCache` that deleting `currency-rates.json` doesn't touch.

Settings shows the last fiat and crypto sync independently. Manual rate refresh is not exposed; the store refreshes automatically on its three-hour cadence. When crypto is disabled, its sync remains `Never` and CoinGecko is not contacted.

Rates come from `CurrencyRateStore` (`Features/Calculator/`, owned by `AppCore`). Fiat rates come from
[Frankfurter](https://frankfurter.dev) — open source, no key, no account, no quota, rates blended
from 84 central banks. Crypto rates are optional and come from [CoinGecko](https://www.coingecko.com).
When crypto is off, Opencast does not contact CoinGecko. Fiat uses one `GET api.frankfurter.dev/v2/rates?base=USD`, ~1.4 KB gzipped. v2 answers
with one flat `{date, base, quote, rate}` row per pair rather than a keyed table, and omits the
base's own row — the store folds both into the `[code: rate]` shape `CurrencyRates` stores.

The merged fiat + crypto table is cached at `~/Library/Caches/<bundle-id>/currency-rates.json`, refreshed
every three hours with a 15-minute retry after a failure. One small Frankfurter request and one small
CoinGecko `/simple/price` request update the snapshot. Age is measured from the persisted `fetchedAt`,
not from launch, so relaunching Opencast never re-fetches a snapshot that is still fresh. Offline, the last snapshot keeps answering; with no snapshot at all
the card says so rather than guessing, and a currency the feed doesn't quote reports
`No exchange rate for <CODE>.` The store hands `CalcEngine.evaluate` a finished `CurrencyRates`
value — the engine never fetches, which is what keeps it Foundation-only and testable. `CalcMemo`
keys its memo on the snapshot's `fetchedAt`, so a fresh table re-evaluates without diffing every rate.

Money rounds to two decimals (`CalcFormatter.currency`), widening to four significant digits below a
cent — in *plain* notation, deliberately not `%g`, so `1 IDR to USD` reads `0.00005539 USD` rather
than `5.539e-05`.

## Result and rendering

`CalcResult` carries an `expression` (left), a `display` / `copyText` payload (right), and optional
`sourceBadge` / `targetBadge` word-name pills. `CalculatorCard` renders it as a two-column card.

When the launcher query evaluates to a result, the card is pinned at the top of the list (flat
selection index 0, shifting rows by one). Enter copies the answer; because it is an unmarked copy,
the normal clipboard poller can retain it in Clipboard History.
