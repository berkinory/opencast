# Architecture

This document describes the boundaries that keep Opencast features independent and the app lifecycle
predictable.

## Layers

```text
Opencast/App          composition root and application lifecycle
Opencast/Features     feature state, behavior, and views
Opencast/DesignSystem shared visual tokens and UI primitives
Opencast/Platform     macOS integration and AppKit adapters
ExtensionHost        isolated JavaScriptCore command process
Extensions           runtime shims, schemas, and first-party packages
Store                reviewed extension catalog
Tools                tests, generators, and build utilities
```

Dependencies should point toward small models and platform adapters. Features may use shared palette
and design-system components, but should not reach into another feature's view hierarchy.

## Composition root

`AppCore` is a `@MainActor` singleton and the only owner of long-lived application state. It creates
stores, managers, coordinators, window controllers, and the extension runtime. `AppDelegate` calls
`start()` at launch and `shutdown()` at termination.

A feature normally contains:

- a store or model that owns persisted and observable state;
- a coordinator that translates user intent into feature operations;
- a palette screen or settings view that renders state and forwards actions.

Add new long-lived objects to `AppCore`, wire callbacks there, and keep SwiftUI views declarative.
Do not introduce a second service locator or a feature-owned singleton.

## Palette and windows

`OpencastApp` declares the menu-bar scene. Other windows are managed with AppKit because the app runs
with accessory activation policy.

- `PaletteWindowController` owns the borderless palette panel, its frame, visibility, and restoration
  of the previously focused app.
- `PaletteViewModel` owns the current mode, query, selection, navigation state, and footer state.
- `RootPaletteView` selects the active screen and routes shared keyboard commands.
- `AuxWindowController` owns Settings, About, and onboarding windows.
- `ToastWindowController` owns non-activating feedback shown after the palette closes.
- `DialogController` is the single route for native confirmations and errors.

The hosting view must not resize the palette window. `PaletteWindowController` is the frame source of
truth so compact and expanded modes keep a stable top edge. While an actions menu is open, input is
frozen instead of resigning the search field; changing first responder moves the field and breaks
keyboard continuity.

The flat palette selection index must always match visible item order. Shared list and grid layouts
own scrolling and row geometry, while each screen maps the index to its feature data.

## Feature boundaries

Feature directories own their behavior end to end. Coordinators handle activation and navigation;
stores handle persistence; views render inputs and results. Cross-feature operations are wired as
closures in `AppCore` instead of calling unrelated global state.

Core algorithms that can run without AppKit or SwiftUI stay framework-light and are compiled directly
by the harnesses in `Tools/`. This includes calculator evaluation, emoji data and grid geometry,
clipboard persistence, launcher ranking and scopes, window geometry, and command models. Keep their
clock, filesystem, and network inputs injectable.

## Persistence and permissions

Preferences, caches, application support data, hotkeys, and permission state must use the current
bundle identifier. Debug builds use `com.opencast.app.dev`, which keeps local development isolated
from the installed release.

Clipboard entries carry an internal pasteboard marker so the capture loop ignores writes made by
Opencast itself. Hotkeys retain their established `KeyboardShortcuts_<name>` preference keys so
existing bindings remain valid.

Networked features ship disabled. The owning store controls consent, checks it at every entry point,
and checks it again after suspension points. Use an ephemeral, cacheless `URLSession` when user data
or opt-out deletion is involved. A missing consent value must select the safe, offline behavior.

Extensions use the same principle at a package boundary. `opencast.json` declares capabilities,
the builder validates them, the package hash binds them, and the native broker enforces them at run
time. Commands execute in the helper process; privileged work stays in narrow Swift providers.

## Concurrency

The project uses Swift 6 strict concurrency. UI state and most coordinators are `@MainActor`. Blocking
file work, application scanning, image decoding, and network requests run outside the main actor.
Values crossing isolation boundaries must be `Sendable`, and raw C or Carbon values must be decoded
before entering actor-isolated code.

Use `NotificationToken` for block observer lifetimes. Preserve explicit teardown where a store owns a
resource such as SQLite. Do not hide isolation problems with unchecked conformance unless the safety
invariant is both necessary and documented.

## Adding a feature

1. Define the state owner and persistence boundary.
2. Put user actions and navigation in a coordinator.
3. Reuse `PaletteListLayout`, `PaletteGridLayout`, palette rows, menus, and theme tokens.
4. Wire ownership and cross-feature callbacks in `AppCore`.
5. Add a standalone harness for pure logic when practical.
6. Add settings only for behavior the user can meaningfully control.
7. Run the narrow test, then `make check`.
