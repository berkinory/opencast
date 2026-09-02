import Foundation

/// Downloads, caches and periodically refreshes the exchange-rate table the calculator's currency
/// conversions run on. Network and disk live here, never in `Core/Calculator/`: the engine is handed
/// a finished `CurrencySource`, which is what keeps it Foundation-only and pure.
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

    /// The newest snapshot, or nil when none has landed.
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

    private let fileURL: URL
    private var pump: Task<Void, Never>?

    init() {
        fileURL = AppPaths.caches().appendingPathComponent("currency-rates.json")

        guard let data = try? Data(contentsOf: fileURL) else { return }
        rates = try? JSONDecoder().decode(CurrencyRates.self, from: data)
    }

    /// The calculator controls whether this source is used; crypto is independently filtered when
    /// its optional setting is disabled.
    func source(cryptoEnabled: Bool) -> CurrencySource {
        return .onWithCrypto(rates, cryptoEnabled: cryptoEnabled)
    }

    /// Starts the refresh loop: fetch whenever the cached snapshot is older than `refreshInterval`,
    /// otherwise sleep exactly until it expires. A failed fetch keeps the stale snapshot and retries
    /// sooner.
    func start(cryptoEnabled: Bool = false) {
        self.cryptoEnabled = cryptoEnabled
        if !cryptoEnabled { removeCryptoRates() }
        fetchesAllowed = true
        pump?.cancel()
        let fetchCryptoImmediately = cryptoEnabled && !hasCryptoRates
        pump = Task { [weak self] in
            var fetchImmediately = fetchCryptoImmediately
            while !Task.isCancelled, let self {
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

    func setCryptoEnabled(_ enabled: Bool) {
        guard enabled != cryptoEnabled else { return }
        cryptoEnabled = enabled
        if !enabled { removeCryptoRates() }
        if enabled, fetchesAllowed { start(cryptoEnabled: true) }
    }

    func stop() {
        fetchesAllowed = false
        pump?.cancel()
        pump = nil
    }

    func refreshNow() async -> Bool {
        guard fetchesAllowed else { return false }
        return await fetchAndStore()
    }

    private func fetchAndStore() async -> Bool {
        guard fetchesAllowed, let fiat = try? await Self.fetchFiat() else {
            return false
        }
        guard fetchesAllowed else { return false }
        let shouldFetchCrypto = cryptoEnabled
        let crypto: [String: Double]?
        if shouldFetchCrypto {
            guard let fetchedCrypto = try? await Self.fetchCrypto() else { return false }
            crypto = fetchedCrypto
        } else {
            crypto = nil
        }
        guard fetchesAllowed, !shouldFetchCrypto || cryptoEnabled else { return false }

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
    /// max-age=…`, so the shared session would write a second copy into the on-disk `URLCache`.
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

        return try CurrencyFeed.fiat(data: data)
    }

    private nonisolated static func fetchCrypto() async throws -> [String: Double] {
        let request = URLRequest(url: cryptoEndpoint, timeoutInterval: 20)
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
            throw URLError(.badServerResponse)
        }

        return try CurrencyFeed.crypto(data: data)
    }
}
