# Development

## Requirements

- macOS 15 or later
- Xcode 26 with the macOS SDK selected by `xcode-select`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen)
- Apple's `swift-format`
- Node.js and Bun when working on extensions or generated data

Install the command-line tools with Homebrew:

```sh
brew install xcodegen swift-format node bun
```

## Daily workflow

```sh
make generate     # regenerate the Xcode project from project.yml
make build        # unsigned Debug build
make run          # build and launch Opencast Dev
make lint         # strict formatting check
make format       # apply Swift formatting
make test         # standalone Swift harnesses
make check        # lint, tests, and Debug build
```

Open `Opencast.xcodeproj` for Xcode development. `project.yml` is the source of truth; never edit the
generated project to add files or change build settings. Commit both files after `make generate`.

The Debug product is `Opencast Dev.app` with bundle identifier `com.opencast.app.dev`. Its preferences,
caches, application support data, login item, and system permissions are separate from the release
app. Keep all new persisted paths based on `Bundle.main.bundleIdentifier`.

If command-line builds use Command Line Tools instead of Xcode, select Xcode first:

```sh
sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
```

## Tests

`make test` compiles small harnesses in `Tools/` against production source files. This keeps core
logic testable without launching the app or creating an XCTest target. Add cases to the nearest
harness when changing matching, parsing, persistence, geometry, shortcuts, or command behavior.

Some files deliberately have narrow dependencies so a harness can compile them directly:

- calculator engine: Foundation-only and pure; inject time, calendar, and exchange rates;
- emoji catalog and palette grid geometry: no AppKit or SwiftUI;
- clipboard store: Foundation and SQLite3 only;
- launcher ranking and search scopes: Foundation only with injected paths and time;
- window command geometry: Foundation and CoreGraphics only.

`Tools/fuzz-test.swift` contains the harness copy of launcher fuzzy matching. When scoring changes,
update the production implementation and its test copy together.

Extension changes use additional checks:

```sh
make extensions-test
make extension-store-test
make extension-budget-test
```

## Generated sources

Do not edit generated Swift files by hand:

```sh
node Tools/gen-emoji.js
node Tools/gen-currencies.js
```

Review and commit the generated diff. The currency generator joins pinned provider and CLDR data;
ambiguous currency nouns remain in the hand-maintained contested table.

## Packaging and releases

Create a local unsigned image with `make unsigned-dmg`. It is for local verification only.

Official releases are built by `.github/workflows/release.yml`. The workflow signs and notarizes the
app, creates Sparkle and DMG artifacts, publishes the GitHub release, and updates the Homebrew cask.
Signing credentials and Sparkle private keys belong in protected CI secrets, never in the repository
or command output.

Before a release:

1. Run `make check` and all extension checks.
2. Confirm `project.yml`, the generated Xcode project, and release notes agree.
3. Verify the signed app, update archive, appcast, and DMG produced by CI.
4. Test both a direct update and the Homebrew upgrade instructions.
