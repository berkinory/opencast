# Hotkeys (in-house, zero dependencies)

`Features/HotKeys/` holds:

- `KeyShortcut` — Sendable model, Carbon keycode + modifiers, layout-aware glyphs via `UCKeyTranslate`.
- `HotKeyCenter` — the Carbon `RegisterEventHotKey` layer, pausable.
- `DoubleCommandMonitor` — the global modifier-event path for the optional double-tap ⌘ binding.

`HotKeyManager` owns both: persistence, conflict lookup, and dispatch. Window management commands use
`KeyboardShortcuts_windowCommand.<id>` keys and are registered even while the feature is disabled; the
AppCore dispatch guard keeps a disabled feature inert without losing saved bindings.

## Persistence

Shortcuts persist as JSON strings under `KeyboardShortcuts_<name>` UserDefaults keys — a **legacy
format** from the removed KeyboardShortcuts package, kept so old bindings survive. Key shortcuts keep
their original JSON shape; double-tap ⌘ uses the `doubleCommand` marker. The set of bound bundle IDs
lives in `boundAppBundleIDs` and is re-registered on launch.

## Recorder

The settings recorder (`Features/Settings/ShortcutRecorder.swift`) is deliberately **not** a focusable
control: the active recorder is `HotKeyManager.recordingAction` state, and keys are captured by local
NSEvent monitors while all Carbon registrations are paused. A double-tap ⌘ is recognized from two
command press/release cycles; any chord key or other modifier cancels that gesture.
