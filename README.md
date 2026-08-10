# Opencast

A native command palette for macOS.

<p align="center">
  <img src="docs/screenshot.png" alt="Opencast command palette" width="720">
</p>

Opencast brings apps, commands, clipboard history, calculations, snippets, quicklinks, emoji,
window management, and extensions into one keyboard-first interface. It is built with SwiftUI and
AppKit for macOS 15 and later.

## Features

- Search and launch applications, commands, and System Settings panes.
- Use clipboard history with text and image previews, pinning, search, and app exclusions.
- Calculate expressions and convert units or currencies directly in the launcher.
- Create snippets and quicklinks, then search or trigger them from the palette.
- Search emoji and symbols with keyboard navigation and skin-tone preferences.
- Move and resize windows with commands or global shortcuts.
- Install capability-scoped extensions from the built-in store or a local package.
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

Networked features are disabled until enabled by the user. Extension capabilities are declared by
each package and enforced by the native host.

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

## Extensions

Extensions are JavaScript or TypeScript commands rendered by a native host. Node.js and Bun are
development tools only; they are not embedded in the app. Each command runs in an isolated helper
process and can access only the capabilities declared in its manifest.

Start from one of the packages in `Extensions/Packages/`. A package contains its metadata, security
contract, and source:

```text
Extensions/Packages/example/
├── package.json
├── opencast.json
└── src/index.tsx
```

`package.json` describes the extension and its commands. `opencast.json` declares command entry
points and privileged capabilities:

```json
{
  "schemaVersion": 1,
  "commands": [
    {
      "name": "example",
      "src": "src/index.tsx",
      "mode": "view",
      "capabilities": {
        "names": ["network.request"],
        "networkDomains": ["api.example.com"]
      }
    }
  ]
}
```

Commands use `view`, `no-view`, or `menu-bar` mode. The compatibility layer provides the supported
parts of `@raycast/api`, `@raycast/utils`, React, and JSX. Unsupported APIs fail explicitly. Prefer
the native `List`, `Grid`, `Detail`, `Form`, and `ActionPanel` surfaces instead of custom rendering.

Build and validate an extension with:

```sh
node Tools/extensions/build-extension.js \
  --package Extensions/Packages/example \
  --out build/extensions/example.ocx

make extensions-test
make extension-store-test
make extension-budget-test
```

The builder rejects undeclared capabilities, native modules, post-install scripts, remote code
loading, direct Node.js APIs, and oversized bundles. Network domains, executable paths, and file
roots must be as narrow as the command allows.

To test locally, build the `.ocx` package and run **Import Extension** in Opencast. To publish, add
the package to `Store/approved-extensions.json`, run all extension checks, and submit the source,
manifest, generated package, and catalog changes together.

## Contributing

Open an issue before starting a large behavior or architecture change. Keep pull requests focused,
match the existing design and architecture, and include tests for logic that can run outside the UI.
Every change must pass `make check`; extension changes must also pass the extension test targets.

Report security vulnerabilities through
[GitHub Security Advisories](https://github.com/berkinory/opencast/security/advisories/new), not a
public issue.

## Credits

Opencast began as a fork of [Tinycast](https://github.com/abue-ammar/tinycast) and continues under
the same AGPL-3.0 license. The current project builds on that foundation with its own architecture,
features, design, and extension platform.

## License

[AGPL-3.0](LICENSE)
