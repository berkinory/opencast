# Opencast

Opencast is a native macOS command palette built with SwiftUI and AppKit. It runs as a menu-bar app on macOS 15+

## Read first

- [Architecture](docs/architecture.md) covers ownership, feature boundaries, windows, persistence,
  extensions, and concurrency.
- [UI](docs/ui.md) covers design tokens, shared palette components, interaction rules, and visual
  review.
- [Development](docs/development.md) covers setup, tests, generated files, and releases.

## Structure

- `Opencast/App/`: app entry point and `AppCore` composition root.
- `Opencast/Features/`: feature models, coordinators, stores, and views.
- `Opencast/DesignSystem/`: shared theme and UI primitives.
- `Opencast/Platform/`: AppKit and operating-system integration.
- `ExtensionHost/`, `Extensions/`, `Store/`: extension runtime, packages, and catalog.
- `Tools/`: standalone test harnesses and generators.

## Working rules

- Preserve `AppCore` as the single owner of long-lived state. Put feature behavior in its coordinator,
  store, or model instead of a SwiftUI view.
- Keep Swift 6 actor boundaries explicit. Move blocking I/O and expensive work off the main actor;
  make values crossing isolation boundaries `Sendable`.
- Reuse palette layouts and `Theme` tokens. Read `docs/ui.md` before changing UI behavior or style.
- Keep network access opt-in and capability-scoped. Re-check consent around asynchronous requests.
- Do not hand-edit generated Swift files or `Opencast.xcodeproj`. Update their source and regenerate.
- Remove dead code instead of adding compatibility paths. Add comments only for non-obvious invariants.

## Validate

```sh
make check
make extensions-test          # when extension runtime or packages change
make extension-store-test     # when package validation or catalog data changes
make generate                 # after editing project.yml
```