# Opencast

A native command palette for macOS.

<p align="center">
  <img src="docs/screenshot.png" alt="Opencast command palette" width="720">
</p>

Opencast brings apps, commands, clipboard history, calculations, snippets, quicklinks, emoji, and
window management into one keyboard-first interface. It is built with SwiftUI and AppKit for macOS
15 and later.

## Features

- Search and launch applications, commands, and System Settings panes.
- Use clipboard history with text and image previews, pinning, search, and app exclusions.
- Calculate expressions and convert units or currencies directly in the launcher.
- Create snippets and quicklinks, then search or trigger them from the palette.
- Search emoji and symbols with keyboard navigation and skin-tone preferences.
- Move and resize windows with commands or global shortcuts.
- Assign global shortcuts to the launcher, features, apps, and commands.
- Receive signed updates through Sparkle, or update with Homebrew when installed as a cask.

## Install

Download the latest signed build from [GitHub Releases](https://github.com/berkinory/opencast/releases/latest),
or install it with Homebrew:

```sh
brew install --cask berkinory/brew/opencast
```

Opencast requires macOS 15 or later.

## Permissions

Opencast requests system permissions only when a feature needs them:

- **Accessibility** lets clipboard items, emoji, and snippets return text to the previously focused
  app. It is also required for window management.
- **Input Monitoring** is required for snippet expansion outside Opencast.

Networked features are disabled until enabled by the user.

## Build

Install Xcode 26, XcodeGen, and Apple's `swift-format`, then run:

```sh
make generate
make check
make run
```

`project.yml` is the source of truth for the Xcode project. Run `make generate` after changing it.
Debug builds use a separate app name, bundle identifier, preferences, caches, and permissions, so
they can run beside an installed release.

See [Development](docs/development.md), [Architecture](docs/architecture.md), and
[UI](docs/ui.md) for the contributor-facing details.

## Contributing

Open an issue before starting a large behavior or architecture change. Keep pull requests focused,
match the existing design and architecture, and include tests for logic that can run outside the UI.
Every change must pass `make check`.

Report security vulnerabilities through
[GitHub Security Advisories](https://github.com/berkinory/opencast/security/advisories/new), not a
public issue.

## Credits

Opencast began as a fork of [Tinycast](https://github.com/abue-ammar/tinycast) and continues under
the same AGPL-3.0 license. The current project builds on that foundation with its own architecture,
features, and design.

## License

[AGPL-3.0](LICENSE)
