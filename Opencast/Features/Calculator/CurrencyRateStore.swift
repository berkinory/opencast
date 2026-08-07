import Foundation

/// Downloads, caches and periodically refreshes the exchange-rate table the calculator's currency
/// conversions run on. Network and disk live here, never in `Core/Calculator/`: the engine is handed
/// a finished `CurrencySource`, which is what keeps it Foundation-only and pure.
///
/// This reaches the network, so it is gated on explicit consent — off until the user enables currency
/// conversion in Settings. Every path that could reach the network or surface a rate re-checks
/// `isEnabled` rather than trusting a caller.
@MainActor
final class CurrencyRateStore: ObservableObject {
    static let fiatProvider = "Frankfurter"
    static let cryptoProvider = "CoinGecko"
    static let provider = "Frankfurter + CoinGecko"
    static let providerURL = URL(string: "https://frankfurter.dev")!
    static let cryptoProviderURL = URL(string: "https://www.coingecko.com")!
    private nonisolated static let endpoint = URL(
        string: "https://api.frankfurter.dev/v2/rates?base=USD")!
    private nonisolated static let cryptoEndpoint: URL = {
        var components = URLComponents(string: "https://api.coingecko.com/api/v3/simple/price")!
        components.queryItems = [
            URLQueryItem(
                name: "ids",
                value: CalcCurrency.cryptoAssets.map(\.id).joined(separator: ",")),
            URLQueryItem(name: "vs_currencies", value: "usd"),
        ]
        return components.url!
    }()
    /// Refresh both fiat and crypto in one lightweight cycle, no more often than every three hours.
    static let refreshInterval: TimeInterval = 3 * 3600
    /// Shorter retry so a machine that was offline at launch picks rates up soon after it reconnects.
    private static let retryInterval: TimeInterval = 15 * 60

    /// Explicit user consent, persisted under the bundle-scoped defaults. Deliberately *not* part of
    /// `AppSettings`, so settings changes cannot silently grant network access.
    @Published private(set) var isEnabled: Bool

    /// The newest snapshot, or nil when none has landed — and always nil while consent is withheld.
    @Published private(set) var rates: CurrencyRates?
    private var cryptoEnabled = false
    private var fetchesAllowed = false

    var lastFiatSync: Date? { rates?.fetchedAt }
    var lastCryptoSync: Date? {
        guard cryptoEnabled,
            rates?.rates.keys.contains(where: Self.cryptoCodes.contains) == true
        else { return nil }
        return rates?.fetchedAt
    }

    private static let consentKey = "currencyRatesEnabled"
    private let defaults = UserDefaults.standard
    private let fileURL: URL
    private var pump: Task<Void, Never>?

    init() {
        // Absent reads as false, which is the only safe default for a network feature.
        isEnabled = defaults.bool(forKey: Self.consentKey)
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")

        // Guard 1 — a disabled feature doesn't even read back a snapshot left on disk.
        guard isEnabled, let data = try? Data(contentsOf: fileURL) else { return }
        rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
    }

    /// What the calculator is allowed to use. Without provider consent the engine is handed `.off`;
    /// crypto is independently filtered when its optional setting is disabled.
    func source(cryptoEnabled: Bool) -> CurrencySource {
        guard isEnabled else { return .off }
        return .onWithCrypto(rates, cryptoEnabled: cryptoEnabled)
    }

    /// Starts the refresh loop: fetch whenever the cached snapshot is older than `refreshInterval`,
    /// otherwise sleep exactly until it expires. A failed fetch keeps the stale snapshot and retries
    /// sooner. Guard 3 — no consent, no loop, so `AppCore.start()` can call this unconditionally.
    func start(cryptoEnabled: Bool = false) {
        self.cryptoEnabled = cryptoEnabled
        if !cryptoEnabled { removeCryptoRates() }
        fetchesAllowed = true
        guard isEnabled else { return }
        // Replace rather than bail on a live pump: a loop that has already exited still leaves a
        // non-nil task behind, and a `pump == nil` guard would let that dead task block every restart.
        pump?.cancel()
        let fetchCryptoImmediately = cryptoEnabled && !hasCryptoRates
        pump = Task { [weak self] in
            var fetchImmediately = fetchCryptoImmediately
            while !Task.isCancelled, let self, self.isEnabled {
                // Clamped: a snapshot stamped in the future (clock skew, an edited cache file) must
                // not park the loop for longer than one interval.
                let age = max(0, self.rates.map { Date().timeIntervalSince($0.fetchedAt) } ?? .infinity)
                guard fetchImmediately || age >= Self.refreshInterval else {
                    try? await Task.sleep(for: .seconds(Self.refreshInterval - age))
                    continue
                }
                fetchImmediately = false
                let ok = await self.fetchAndStore()
                try? await Task.sleep(for: .seconds(ok ? Self.refreshInterval : Self.retryInterval))
            }
        }
    }

    /// The Settings toggle's only entry point, called after the user accepts the consent dialog.
    /// Disabling tears the loop down, drops the snapshot and deletes the cached file — opting out
    /// shouldn't leave downloaded data behind.
    func setCryptoEnabled(_ enabled: Bool) {
        guard enabled != cryptoEnabled else { return }
        cryptoEnabled = enabled
        if !enabled { removeCryptoRates() }
        if enabled, isEnabled, fetchesAllowed { start(cryptoEnabled: true) }
    }

    func stop() {
        fetchesAllowed = false
        pump?.cancel()
        pump = nil
    }

    func setEnabled(_ enabled: Bool) {
        guard enabled != isEnabled else { return }
        isEnabled = enabled
        defaults.set(enabled, forKey: Self.consentKey)
        if enabled {
            start(cryptoEnabled: cryptoEnabled)
        } else {
            fetchesAllowed = false
            pump?.cancel()
            pump = nil
            rates = nil
            try? FileManager.default.removeItem(at: fileURL)
        }
    }

    /// Manual "Update Now" from Settings. Returns whether a fresh table landed, so the pane can say
    /// the fetch failed instead of leaving the button to spring back with nothing changed.
    func refreshNow() async -> Bool {
        guard isEnabled, fetchesAllowed else { return false }
        return await fetchAndStore()
    }

    private func fetchAndStore() async -> Bool {
        // Guard 4 — re-checked at the network boundary itself: the pump may have been sleeping when
        // the user revoked consent, and this is the last line before a request goes out.
        guard isEnabled, fetchesAllowed, let fiat = try? await Self.fetchFiat() else {
            return false
        }
        guard isEnabled, fetchesAllowed else { return false }
        let shouldFetchCrypto = cryptoEnabled
        let crypto: [String: Double]?
        if shouldFetchCrypto {
            guard let fetchedCrypto = try? await Self.fetchCrypto() else { return false }
            crypto = fetchedCrypto
        } else {
            crypto = nil
        }
        // Re-check after every await: consent or the optional crypto feature can be withdrawn while a response is in flight.
        guard isEnabled, fetchesAllowed, !shouldFetchCrypto || cryptoEnabled else { return false }

        var merged = fiat.rates
        if let crypto {
            for (code, rate) in crypto { merged[code] = rate }
        }
        let fetched = CurrencyRates(base: fiat.base, rates: merged, fetchedAt: Date())
        rates = fetched
        if let data = try? JSONEncoder().encode(fetched) {
            try? data.write(to: fileURL, options: .atomic)
        }
        return true
    }

    /// Deliberately not `URLSession.shared`: the provider serves the table `Cache-Control: public,
    /// max-age=…`, so the shared session would write a second copy into the on-disk `URLCache` that
    /// `setEnabled(false)` never deletes. Cacheless, so revoking consent really does leave nothing behind.
    private nonisolated static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.urlCache = nil
        return URLSession(configuration: config)
    }()

    /// Off-main by way of `URLSession`'s async API; the decoded table is a plain value, so nothing but `CurrencyRates` crosses back.
    private func removeCryptoRates() {
        guard let rates else { return }
        let cryptoCodes = Self.cryptoCodes
        let fiatRates = rates.rates.filter { !cryptoCodes.contains($0.key) }
        let cleaned = CurrencyRates(base: rates.base, rates: fiatRates, fetchedAt: rates.fetchedAt)
        self.rates = cleaned
        if let data = try? JSONEncoder().encode(cleaned) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    private static let cryptoCodes = Set(CalcCurrency.cryptoAssets.map(\.code))

    private var hasCryptoRates: Bool {
        rates?.rates.keys.contains(where: Self.cryptoCodes.contains) == true
    }

    private nonisolated static func fetchFiat() async throws -> CurrencyRates {
        let request = URLRequest(url: endpoint, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        // Frankfurter v2 answers with one flat row per pair rather than a keyed table.
        let rows = try JSONDecoder().decode([RateRow].self, from: data)
        guard let base = rows.first?.base else { throw URLError(.cannotParseResponse) }
        var rates: [String: Double] = [:]
        rates.reserveCapacity(rows.count + 1)
        for row in rows where row.rate > 0 && row.rate.isFinite && row.base == base {
            rates[row.quote] = row.rate
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        rates[base] = 1

        return CurrencyRates(base: base, rates: rates, fetchedAt: Date())
    }

    private nonisolated static func fetchCrypto() async throws -> [String: Double] {
        let request = URLRequest(url: cryptoEndpoint, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        let payload = try JSONDecoder().decode([String: CryptoQuote].self, from: data)
        var rates: [String: Double] = [:]
        for asset in CalcCurrency.cryptoAssets {
            guard let price = payload[asset.id]?.usd, price > 0, price.isFinite else { continue }
            rates[asset.code] = 1 / price
        }
        guard !rates.isEmpty else { throw URLError(.cannotParseResponse) }
        return rates
    }

    private struct RateRow: Decodable {
        let base: String
        let quote: String
        let rate: Double
    }

    private struct CryptoQuote: Decodable {
        let usd: Double
    }
}
