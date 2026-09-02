import SwiftUI

struct CalculatorSettingsView: View {
    @ObservedObject private var settings = AppCore.shared.settings
    @ObservedObject private var currencyRates = AppCore.shared.currencyRates

    var body: some View {
        SettingsPane(
            title: "Calculator",
            subtitle: "Calculate directly from launcher search.",
            systemImage: "function",
            tint: Theme.Colors.calculatorAccent
        ) {
            SettingsFeatureToggleRow(
                title: "Calculator",
                systemImage: "function",
                tint: Theme.Colors.calculatorAccent,
                isEnabled: $settings.calculatorEnabled
            )

            SettingsSection(
                header: "Conversions",
                subtitle: "Choose which currency results the calculator can return.",
                systemImage: "arrow.left.arrow.right",
                tint: Theme.Colors.calculatorAccent
            ) {
                SettingsControlRow(
                    title: "Currency conversion",
                    subtitle: "Convert between supported fiat currencies.",
                    destination: .currencyConversion
                ) {
                    Toggle(
                        "Currency conversion",
                        isOn: Binding(
                            get: { settings.currencyConversionEnabled },
                            set: { enabled in setCurrencyConversionEnabled(enabled) }
                        )
                    )
                    .settingsToggle()
                }

                SettingsRowDivider()
                SettingsControlRow(
                    title: "Crypto conversion",
                    subtitle: "Include supported cryptocurrencies in conversions.",
                    destination: .cryptoConversion
                ) {
                    Toggle(
                        "Crypto conversion",
                        isOn: Binding(
                            get: { settings.cryptoConversionEnabled },
                            set: { enabled in setCryptoConversionEnabled(enabled) }
                        )
                    )
                    .settingsToggle()
                    .disabled(!settings.currencyConversionEnabled)
                }
            }
            .disabled(!settings.calculatorEnabled)
            .opacity(settings.calculatorEnabled ? 1 : 0.42)
        }
        .onChange(of: settings.calculatorEnabled) { _, enabled in
            if enabled, settings.currencyConversionEnabled {
                currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
            } else {
                currencyRates.stop()
            }
        }
    }

    private func setCurrencyConversionEnabled(_ enabled: Bool) {
        settings.currencyConversionEnabled = enabled
        if enabled {
            currencyRates.start(cryptoEnabled: settings.cryptoConversionEnabled)
        } else {
            currencyRates.stop()
        }
    }

    private func setCryptoConversionEnabled(_ enabled: Bool) {
        settings.cryptoConversionEnabled = enabled
        currencyRates.setCryptoEnabled(enabled)
    }
}
