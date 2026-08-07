# App launcher & fuzzy match

`AppIndex.scan()` runs off-main, enumerates the user-editable search scopes, and dedups by bundle ID
(the earliest scope wins).

## Search scopes

`SearchScopes` owns the folders and individual `.app` bundles Opencast indexes. The list is editable
under Settings → Launcher → Search and stored as tilde-abbreviated paths in `AppSettings`.

Enumeration is flat: one directory listing per scope, plus a single targeted listing of each app's
`Contents/Applications` folder for embedded launchable apps. It never walks arbitrary app contents or nested
folders, so embedded helpers and resources do not fill the launcher or slow rescans. Add a nested folder as
its own scope.

The defaults cover the standard Applications folders, system Utilities, the cryptex-delivered system
applications, the user's `~/Applications`, and Finder as an individual bundle. Finder is not exposed by
scanning all of `/System/Library/CoreServices`, because that directory also contains many background
agents and there is no safe metadata filter that keeps every launchable app.

A missing scope is skipped and shown as a warning. Editing the list triggers a re-index immediately;
overlapping refreshes collapse into one trailing scan.

`FuzzyMatch` classifies matches as exact → prefix → word-start → substring → subsequence, with
consecutive / word-boundary detail scoring inside each class. `LauncherRankingStore` learns an
adaptive query affinity: one choice nudges results within the same class, while three recent choices
may promote a word-start or substring match by exactly one class. Exact matches remain absolute,
prefixes never become exact, and weak subsequences never receive a class promotion. This lets a
repeated `ch` → Google Chrome choice overtake the default prefix match Chess without allowing an
unrelated frequent app to surface. Matching strips invisible Unicode format scalars first, since app
metadata can contain bidi/zero-width markers before the visible name. App names with Han characters also get
precomputed pinyin aliases for full readings and per-character initials; literal matches always rank above
romanized aliases.

Selecting a launcher result records every prefix of the submitted query, so choosing WhatsApp for
`wha` also teaches `w`, `wh`, and `wha`. Every palette launch also records weak item-wide usage,
including empty-query favorites; it is only a final tie-break and can never change a fuzzy match
class. Direct hotkeys remain excluded because toggling an app outside Root Search provides no query
intent. Query affinity has a 30-day half-life, global usage a 60-day half-life, and repeated visits
approach a ceiling with diminishing returns, so stale habits yield quickly instead of becoming permanent. Learned
data stays on device in `launcher-ranking.json`; a ranked result offers a per-item reset in its
Actions menu, and users can clear all learned ranking in General Settings.

Rankings are memoized one query deep and keyed by the ranking store's revision, so a launch or reset
invalidates the cached order. `rank` resolves the query and global affinity tables once per pass — one
fold and one clock read per table, not per candidate.

> **Invariant:** `Tools/fuzz-test.swift` contains a **copy** of `FuzzyMatch` from
> `Opencast/Features/Launcher/AppIndex.swift`. If you change the scoring in one, mirror it in the other or the test
> is meaningless.

The ranking harness covers prefix learning, frequency/recency scoring, persistence, and both reset
paths; see the command in `development.md`.

Icons go through a count-capped `NSCache` (`IconCache`).

## Uninstall Application

Application actions include a guarded uninstall flow. Opencast identifies the app bundle by its path and bundle ID, checks common per-user remnants in Application Support, Caches, Containers, Group Containers, preferences, saved state, logs, WebKit, HTTP storage, and user launch agents, then shows the exact paths before confirmation. The app and confirmed user files are moved to the Trash, not permanently deleted. Running apps are asked to quit first. System-owned remnants are reported but left untouched when administrator authorization would be required.

Matching is conservative: Opencast uses exact bundle-ID/name matches and does not recursively sweep arbitrary home-directory data. This avoids the dangerous false positives that generic name-based cleanup can cause.

## Reveal in Finder

Application and System Settings results expose **Show in Finder** in their ⌘K Actions menu and on
**⌘↵**. Synthetic command results do not have a filesystem location, so the shortcut is unavailable
for them.

## Quitting apps

`RunningAppsMonitor` (live from `NSWorkspace` launch/terminate notifications) drives both the row's
running dot and the availability of the quit actions:

- **Quit Application** — the last row of an app's ⌘K Actions menu, shown only while that app is
  running. `AppLauncher.quit(bundleID:)` terminates every instance of the bundle and reports whether
  anything was running; the palette only dismisses when something was, and it restores focus unless
  the app it just quit *was* `previousApp`.
- **Quit All Applications** — a Command. `AppLauncher.quitAllTargets()` is the policy (every
  `.regular` app except Finder — `terminate()` only relaunches it — and Opencast, excluded by PID
  because About/Settings temporarily flips it to `.regular`). `AppCore.quitAllApps()` resolves that
  list **once**, confirms it with `NativeConfirmation`, then terminates exactly what was confirmed. The palette
  hides before the alert — it is a floating panel and would sit above it.

## Commands

Commands include Sleep, Sleep Displays, Restart, Shut Down, Log Out, Show Screen Saver,
Play / Pause, Next Track, Previous Track, volume controls, Show Desktop, Toggle System Appearance,
Open Trash, Empty Trash, Eject All Disks, Toggle Hidden Files, Hide All Apps Except Frontmost, and
Unhide All Hidden Apps. Caffeinate starts macOS's built-in keep-awake assertion, Decaffeinate stops
running `caffeinate` processes, and Caffeinate For accepts hours, minutes, and seconds as inline
arguments. Optional Window Management commands add tiling, sizing, moving, display, and fullscreen
actions. Eject All Disks ejects local volumes Finder marks as ejectable. Keyboard-event
commands require Accessibility permission; automation commands require
Automation permission. The Commands settings category controls both built-in and system actions.

Both quits are graceful `NSRunningApplication.terminate()`, so an app with unsaved work still puts up
its own save sheet.

The ⌘K menu samples `isRunning` **once, when it opens** (`RootPaletteView.openActions()`), so an app
launching or quitting elsewhere can't add or drop the Quit row while the menu is up — the same freeze
the rest of the menu already has ([palette.md](palette.md)). Only `LauncherList` observes
`RunningAppsMonitor` live, for the running dot.
