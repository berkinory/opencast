# Development

How to build and test Opencast.

## Requirements

- macOS 15 or later. macOS 26 adds the native Liquid Glass surface; older supported systems use the solid fallback.
- Xcode 26 installed — it provides the SwiftUI macro plugin and SDK used to build.

## First-time setup

For local development, no Apple account is required:

```sh
make build
```

## Make targets

The repository uses Apple's `swift-format` for formatting and strict style checks. The compiler remains
the semantic checker; `make` runs formatting checks, standalone tests, and a build.

```sh
make check                                # lint + tests + Debug build
make format                               # format Opencast/ and Tools/
make lint
make build                                # local unsigned Debug build
make run                                  # build and launch Opencast Dev
make generate                             # regenerate Opencast.xcodeproj from project.yml
```

Install the local tools once with `brew install swift-format xcodegen`.

## Build & run

Open the project in Xcode for editing:

```sh
open Opencast.xcodeproj
```

For a local run without an Apple account:

```sh
make run
```

`xcodebuild` uses whatever `xcode-select` points at; if that's the Command Line Tools rather than
Xcode, prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer` (the SwiftUI
`@State`/`@FocusState` macros need Xcode's macOS platform).

`Opencast.xcodeproj` is committed and generated from `project.yml` via
[XcodeGen](https://github.com/yonaskolb/XcodeGen) — after changing project settings in `project.yml`,
run `xcodegen generate` and commit the result.

### The dev build

Debug builds are isolated from the release: **`Opencast Dev.app`**, bundle id `com.opencast.app.dev`. Since
every persisted thing is keyed by bundle
id — `~/Library/Preferences/<id>.plist` (settings + hotkey bindings),
`~/Library/Caches/<id>/` (clipboard history, exchange rates, frequent emoji),
`~/Library/Application Support/<id>/` (the onboarding marker), the `SMAppService` login item, and the
Accessibility / Input Monitoring (TCC) grants — a build you run locally can't read or clobber the
installed app's state, and both can run side-by-side.

Consequences worth knowing:

- The dev build asks for Accessibility on its own the first time, and starts with **no** hotkeys bound
  and onboarding unseen. Grant + bind once; the fixed build path and bundle id keep local state stable.
  `make build` is unsigned by default; Xcode can use Apple Development signing if an account is available.
- Don't bind the same global hotkey in both — whichever registered first wins.

### Editor (VS Code) code-intelligence

Autocomplete / go-to-definition come from SourceKit-LSP driven by a `buildServer.json`. Generate it
once (it's machine-specific and git-ignored):

```sh
brew install xcode-build-server
xcode-build-server config -project Opencast.xcodeproj -scheme Opencast \
    --build_root "$PWD/build/DerivedData"
```

`--build_root` matches the fixed path the VS Code build task / F5 use, so the editor indexes what you
actually build. Do a build once (⌘⇧B or F5) to populate it. In VS Code, **F5** builds and launches the
app; changes always apply (fixed build path — no need to delete `build/`).

## Tests

There's no XCTest target. Standalone harnesses:

```sh
swift Tools/fuzz-test.swift                                        # launcher fuzzy matcher
swiftc -swift-version 6 Opencast/Features/Launcher/LauncherRankingStore.swift Tools/ranking-test.swift \
    -o /tmp/ranking-test && /tmp/ranking-test                      # learned launcher ranking
swiftc -swift-version 6 Opencast/Features/Launcher/SearchScopes.swift Tools/scopes-test.swift \
    -o /tmp/scopes-test && /tmp/scopes-test                       # launcher search scopes
swiftc Opencast/Features/Calculator/Engine/*.swift Tools/calc-test.swift \
    -o /tmp/calc-test && /tmp/calc-test                           # calculator engine
swiftc -swift-version 6 Opencast/Features/Clipboard/ClipboardStore.swift Tools/clipboard-test.swift \
    -o /tmp/clipboard-test && /tmp/clipboard-test                 # clipboard store
swiftc -swift-version 6 Opencast/Features/WindowManagement/WindowCommand.swift \
    Opencast/Features/WindowManagement/WindowLayout.swift \
    Opencast/Features/WindowManagement/WindowActionMemory.swift Tools/window-command-test.swift \
    -o /tmp/window-command-test && /tmp/window-command-test        # window geometry
swiftc -swift-version 6 Opencast/Features/Palette/PaletteSelectionIndex.swift \
    Tools/palette-selection-test.swift \
    -o /tmp/palette-selection-test && /tmp/palette-selection-test  # palette selection geometry
```

`Tools/fuzz-test.swift` holds a **copy** of `FuzzyMatch` from `Opencast/Features/Launcher/AppIndex.swift` —
change the scoring in one and mirror it in the other. The calc harness compiles the real engine
sources, which is why `Opencast/Features/Calculator/Engine/` must stay Foundation-only.

The clipboard harness likewise compiles the real `ClipboardStore.swift`, so that file must keep to
Foundation + SQLite3 and depend on no other app source. Each case drives a store rooted in a
throwaway temp directory (`ClipboardStore(directory:)`), so a run can never reach a real history.

## Generated data

Two Swift files are emitted by scripts and must never be hand-edited. Both download their source, so
run them online, then commit the result:

```sh
node Tools/gen-emoji.js            # -> Opencast/Features/Emoji/EmojiData.generated.swift
node Tools/gen-currencies.js       # -> Opencast/Features/Calculator/Engine/CurrencyData.generated.swift
```

`gen-currencies.js` joins two sources on the ISO code: **Frankfurter**'s currency list (the same feed
`CurrencyRateStore` fetches rates from, so the table and the rate source can't drift apart) and
**Unicode CLDR**'s `en` currency data, which supplies display names, signs and the singular/plural
noun. It reads the pinned `cldr-json` checkout rather than the host's `Intl`, whose output shifts
with the local ICU version and would make the file unreproducible.

Only unambiguous data is emitted. Anything two currencies claim — `dollars`, `pounds`, `krona` — is
left out and decided by hand in `CalcCurrency.contested`, the one currency table still written by
hand. Re-run the script when a currency is added or retired; nothing breaks in the meantime, since
an unquoted code just reports "no exchange rate".

## Local packaging

A contributor can create an unsigned local DMG without Apple credentials:

```sh
make unsigned-dmg
```

Do not distribute that artifact.

## Release notes

The release workflow reads the matching version section from `CHANGELOG.md` when it exists. The same text
appears on the GitHub Release and in the Sparkle update window. Add the section in the same change as the
`MARKETING_VERSION` bump:

```md
## [0.1.0] - 2026-08-01

### Added

- a concise user-facing change
```

The section is optional. If it is missing, the release contains only the generated requirements block.
