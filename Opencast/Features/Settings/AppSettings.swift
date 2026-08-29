import AppKit
import SwiftUI

/// UserDefaults keys shared between `@AppStorage` call sites so the App and the Settings UI bind to the same key.
enum SettingsKey {
    /// Menu-bar icon visibility — read by `MenuBarExtra(isInserted:)` and the Settings toggle.
    static let showInMenuBar = "showInMenuBar"
}

enum PopToRootTimeout: Int, CaseIterable, Identifiable, Sendable {
    case immediately = 0
    case afterFive = 5
    case afterFifteen = 15
    case afterThirty = 30
    case afterSixty = 60
    case afterNinety = 90

    var id: Int { rawValue }

    var title: String {
        self == .immediately ? "Immediately" : "After \(rawValue) seconds"
    }

    var interval: TimeInterval { TimeInterval(rawValue) }
}

@MainActor
final class AppSettings: ObservableObject {
    private let defaults = UserDefaults.standard
    private var isUpdatingLaunchAtLogin = false
    private enum Key {
        static let clipboardRetention = "clipboardRetentionDays"
        static let clipboardEnabled = "clipboardEnabled"
        static let clipboardDisabledApps = "clipboardDisabledApps"
        static let snippetsEnabled = "snippetsEnabled"
        static let emojiSkinTone = "emojiSkinTone"
        static let emojiEnabled = "emojiEnabled"
        static let popToRootTimeout = "popToRootTimeout"
        static let compactMode = "compactMode"
        static let showFavoritesInCompactMode = "showFavoritesInCompactMode"
        static let currencyConversionEnabled = "currencyConversionEnabled"
        static let cryptoConversionEnabled = "cryptoConversionEnabled"
        static let calculatorEnabled = "calculatorEnabled"
        static let searchScopes = "launcherSearchScopes"
        static let windowManagementEnabled = "windowManagementEnabled"
        static let windowRespectSystemMargins = "windowRespectSystemMargins"
        static let snippetDisabledApps = "snippetDisabledApps"
        static let quicklinksEnabled = "quicklinksEnabled"
        static let hyperKeyEnabled = "hyperKeyEnabled"
        static let hyperKey = "hyperKey"
        static let hyperTapBehavior = "hyperTapBehavior"
    }

    var onHyperKeySettingsChanged: (() -> Void)?

    @Published var searchScopes: [String] {
        didSet { defaults.set(searchScopes, forKey: Key.searchScopes) }
    }

    @Published var clipboardRetention: ClipboardRetention {
        didSet { defaults.set(clipboardRetention.rawValue, forKey: Key.clipboardRetention) }
    }

    @Published var clipboardEnabled: Bool {
        didSet { defaults.set(clipboardEnabled, forKey: Key.clipboardEnabled) }
    }

    /// Bundle IDs whose clipboard changes are never recorded. Ordered so the Settings list is stable.
    @Published var clipboardDisabledApps: [String] {
        didSet { defaults.set(clipboardDisabledApps, forKey: Key.clipboardDisabledApps) }
    }

    @Published var launchAtLogin: Bool {
        didSet {
            guard !isUpdatingLaunchAtLogin else { return }
            do {
                try LaunchAtLogin.set(launchAtLogin)
                launchAtLoginError = nil
            } catch {
                NSLog("Opencast: launch-at-login change failed: \(error.localizedDescription)")
                launchAtLoginError =
                    "macOS rejected the change. Check System Settings > General > Login Items."
                let actualValue = LaunchAtLogin.isEnabled
                guard launchAtLogin != actualValue else { return }
                isUpdatingLaunchAtLogin = true
                launchAtLogin = actualValue
                isUpdatingLaunchAtLogin = false
            }
        }
    }
    @Published private(set) var launchAtLoginError: String?

    /// Preferred skin tone applied to modifier-capable emoji at render and copy time.
    @Published var emojiSkinTone: EmojiSkinTone {
        didSet { defaults.set(emojiSkinTone.rawValue, forKey: Key.emojiSkinTone) }
    }

    @Published var emojiEnabled: Bool {
        didSet { defaults.set(emojiEnabled, forKey: Key.emojiEnabled) }
    }

    /// How long a closed palette keeps its state before popping back to the root launcher.
    @Published var popToRootTimeout: PopToRootTimeout {
        didSet { defaults.set(popToRootTimeout.rawValue, forKey: Key.popToRootTimeout) }
    }

    /// Summon the launcher as a slim search bar that expands into the full list on typing.
    @Published var compactMode: Bool {
        didSet { defaults.set(compactMode, forKey: Key.compactMode) }
    }

    /// Pin favorite app icons to the right of the compact search bar (⌘1–⌘5 to launch).
    @Published var showFavoritesInCompactMode: Bool {
        didSet { defaults.set(showFavoritesInCompactMode, forKey: Key.showFavoritesInCompactMode) }
    }

    @Published var currencyConversionEnabled: Bool {
        didSet { defaults.set(currencyConversionEnabled, forKey: Key.currencyConversionEnabled) }
    }

    @Published var cryptoConversionEnabled: Bool {
        didSet { defaults.set(cryptoConversionEnabled, forKey: Key.cryptoConversionEnabled) }
    }

    @Published var calculatorEnabled: Bool {
        didSet { defaults.set(calculatorEnabled, forKey: Key.calculatorEnabled) }
    }

    @Published var windowManagementEnabled: Bool {
        didSet { defaults.set(windowManagementEnabled, forKey: Key.windowManagementEnabled) }
    }

    @Published var windowRespectSystemMargins: Bool {
        didSet { defaults.set(windowRespectSystemMargins, forKey: Key.windowRespectSystemMargins) }
    }

    @Published var snippetsEnabled: Bool {
        didSet { defaults.set(snippetsEnabled, forKey: Key.snippetsEnabled) }
    }

    /// Bundle IDs whose snippet keywords are never expanded.
    @Published var snippetDisabledApps: [String] {
        didSet { defaults.set(snippetDisabledApps, forKey: Key.snippetDisabledApps) }
    }

    @Published var quicklinksEnabled: Bool {
        didSet { defaults.set(quicklinksEnabled, forKey: Key.quicklinksEnabled) }
    }

    @Published var hyperKeyEnabled: Bool {
        didSet {
            defaults.set(hyperKeyEnabled, forKey: Key.hyperKeyEnabled)
            onHyperKeySettingsChanged?()
        }
    }

    @Published var hyperKey: HyperKey {
        didSet {
            defaults.set(hyperKey.rawValue, forKey: Key.hyperKey)
            onHyperKeySettingsChanged?()
        }
    }

    @Published var hyperTapBehavior: HyperTapBehavior {
        didSet {
            defaults.set(hyperTapBehavior.rawValue, forKey: Key.hyperTapBehavior)
            onHyperKeySettingsChanged?()
        }
    }

    init() {
        // integer(forKey:) returns 0 when unset, which no case matches — falls through to 3 Months.
        clipboardRetention =
            ClipboardRetention(rawValue: defaults.integer(forKey: Key.clipboardRetention))
            ?? .threeMonths
        clipboardEnabled =
            defaults.object(forKey: Key.clipboardEnabled) == nil
            || defaults.bool(forKey: Key.clipboardEnabled)
        // Password managers are excluded out of the box; the defaults apply only until the user first edits the list.
        clipboardDisabledApps =
            defaults.stringArray(forKey: Key.clipboardDisabledApps)
            ?? ["com.apple.keychainaccess", "com.apple.Passwords"]
        launchAtLogin = LaunchAtLogin.isEnabled
        emojiSkinTone =
            defaults.string(forKey: Key.emojiSkinTone).flatMap(EmojiSkinTone.init) ?? .none
        emojiEnabled =
            defaults.object(forKey: Key.emojiEnabled) == nil
            || defaults.bool(forKey: Key.emojiEnabled)
        popToRootTimeout =
            PopToRootTimeout(rawValue: defaults.integer(forKey: Key.popToRootTimeout))
            ?? .immediately
        compactMode = defaults.bool(forKey: Key.compactMode)
        // Defaults to true, so absence must be distinguished from a stored `false`.
        showFavoritesInCompactMode =
            defaults.object(forKey: Key.showFavoritesInCompactMode) == nil
            || defaults.bool(forKey: Key.showFavoritesInCompactMode)
        currencyConversionEnabled =
            defaults.object(forKey: Key.currencyConversionEnabled) == nil
            || defaults.bool(forKey: Key.currencyConversionEnabled)
        cryptoConversionEnabled = defaults.bool(forKey: Key.cryptoConversionEnabled)
        calculatorEnabled =
            defaults.object(forKey: Key.calculatorEnabled) == nil
            || defaults.bool(forKey: Key.calculatorEnabled)
        windowManagementEnabled = defaults.bool(forKey: Key.windowManagementEnabled)
        windowRespectSystemMargins =
            defaults.object(forKey: Key.windowRespectSystemMargins) == nil
            || defaults.bool(forKey: Key.windowRespectSystemMargins)
        snippetsEnabled =
            defaults.object(forKey: Key.snippetsEnabled) == nil
            || defaults.bool(forKey: Key.snippetsEnabled)
        snippetDisabledApps = defaults.stringArray(forKey: Key.snippetDisabledApps) ?? []
        quicklinksEnabled =
            defaults.object(forKey: Key.quicklinksEnabled) == nil
            || defaults.bool(forKey: Key.quicklinksEnabled)
        hyperKeyEnabled = defaults.bool(forKey: Key.hyperKeyEnabled)
        hyperKey = HyperKey(rawValue: defaults.string(forKey: Key.hyperKey) ?? "") ?? .capsLock
        hyperTapBehavior =
            HyperTapBehavior(rawValue: defaults.string(forKey: Key.hyperTapBehavior) ?? "")
            ?? .nothing
        searchScopes = SearchScopes.normalize(
            defaults.stringArray(forKey: Key.searchScopes) ?? SearchScopes.defaults)
    }
}
