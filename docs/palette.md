# Palette

The command palette is a borderless floating `NSPanel` hosting SwiftUI; see
[architecture.md](architecture.md) for window ownership.

## State flow

`PaletteViewModel` (`Features/Palette/PaletteModel.swift`) is the bridge between the panel and
`AppCore`. Showing the palette calls `prepare(mode:)`, which resets state and bumps `focusToken` (a
UUID) so the SwiftUI search field re-focuses. `RootPaletteView` switches its content on `mode`:

- `.launcher` → `LauncherList`
- `.clipboard` → `ClipboardList` + preview

Clipboard is a sub-screen reached from the launcher (Tab, a command, or a hotkey) and back out to it. Command navigation remembers the launcher's query, clears the sub-screen filter, and restores that query with all text selected when returning to the launcher.

The flat `selection` index is the single source of truth for highlight / activation and **must always
match the visible row order**, including the inline calculator card at index 0 when present (see
[calculator.md](calculator.md)).

## Window placement

The palette resolves `NSEvent.mouseLocation` against `NSScreen.screens` when it is summoned, so it
always opens on the display under the pointer. The resolved anchor is cached for the session so
compact and expanded resizing keeps the same top edge, then cleared on hide.

## Menu-open input freeze

While a footer popover menu (⌘K Actions / app menu) is open the search field reads as inert but
**never resigns first responder** — resigning makes the `NSTextField` swap between its field-editor
and cell rendering, shifting the text / placeholder a point or two, so focus stays put. Input is
frozen instead:

- `RootPaletteView` mirrors the open state into `PaletteViewModel.menuOpen`, whose `didSet` fires
  `onMenuOpenChanged`.
- `PalettePanel.sendEvent` then swallows text-editing keystrokes while `menuOpen` (letting ⌘/⌥ chords
  and menu-nav keys through to SwiftUI `onKeyPress`).
- The caret is hidden by clearing SwiftUI's **own** live field editor's `insertionPointColor`. SwiftUI
  force-casts its field editor to a private subclass, so vending a custom one crashes — only the
  existing one can be tuned.

## Escape behavior

Escape follows the same back-out hierarchy as the search field:

1. close an open footer menu;
2. clear a non-empty query;
3. return Clipboard or Emoji to the launcher when the query is empty;
4. hide the palette when the launcher is already at an empty query.

`AppCore.handlePaletteEscape()` owns the state transition; `RootPaletteView` only handles the menu-first rule.

## Focus restoration (load-bearing)

`PaletteWindowController` records `previousApp` (the frontmost app) on show. Paste then targets that
app:

- `Paster.paste` activates it and posts a synthetic ⌘V via `CGEvent`.
- `Paster.pasteInPlace` posts ⌘V straight to the app's PID _without_ activating it, so the palette can
  stay open and frontmost (used by "paste keeping window open").

Both require the Accessibility permission (`Permissions.ensureAccessibility()`).

The same show also mirrors that app into `PaletteViewModel.pasteTarget` (a `PasteTarget`: localized
name + bundle path), so Clipboard and Emoji can name it — the footer pill reads "Paste to Notes" and
the ⌘K paste rows carry the app's icon. Resolved once per summon, never per render, and deliberately
not cleared by `prepare` (pop-to-root resets the screen, not the target).
