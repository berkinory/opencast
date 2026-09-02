# Changelog

## [0.2.4]

### Improved

- Currency conversion now starts automatically, while crypto conversion stays off until enabled.
- Applications can be found using their localized system display names.
- Every built-in command can now have its own keyboard shortcut.

### Fixed

- Fixed currency conversion appearing enabled while exchange rates were not running.
- Fixed Hyper Key tap replay carrying modifier keys into the next shortcut.
- Fixed Eject All Disks missing external drives that report fixed media.

## [0.2.3]

### Added

- Added a quick way to reveal existing file and folder paths in Finder from the launcher and clipboard actions.
- Added Hyper Key support with selectable keys and tap behavior.

### Improved

- Kept clipboard history and learned launcher preferences safe from automatic cache cleanup.
- Kept hidden or disabled launcher categories from responding to their global shortcuts.
- Found applications stored one folder deep inside application directories.
- Added a safe restart action for running applications.
- Reduced repeated work during launcher and feature searches.
- Added three-quarter window layouts for wider side-by-side workspaces.
- Prevented menus from selecting a row beneath the pointer when they open.
- Made it possible to use a currency conversion inside a larger calculation.
- Recognized RMB and Renminbi as names for the Chinese Yuan.

### Fixed

- Fixed the search hint overlapping text while typing with an input method.

## [0.2.2]

### Removed

- Removed the experimental extension platform, including its JavaScript host, capability broker,
  package store, scheduler, and CI tooling. The platform did not reach the compatibility and
  security bar required for a stable release and added disproportionate runtime and maintenance
  surface to the core application.

### Improved

- Calculator no longer shows an error for unsupported conversions.
- Removed redundant checks from the standalone test tools.
- Kept exchange-rate parsing small, shared, and easier to verify without network access.
- Added clipboard filters for text, images, links, and email while keeping pinned items in order.
- Kept selected grid items visible while navigating around the palette bars.
- Made the palette cursor settle consistently between the search field and the rest of the window.
- Kept built-in shortcut labels and actions in one command definition.

## [0.2.1]

### Improved

- Unified local and CI release archive builds and DMG layout through `build-dmg.sh`.
- Added familiar Control-key navigation to emoji and extension grids.
- Made built-in and extension grids scroll and select items consistently.
- Reduced launcher pauses and unnecessary background wake-ups.
- Showed uninstall results sooner and made their file sizes match Finder more closely.
- Kept Settings in front when the launcher is opened and closed over it.
- Made Command-Q close Settings without quitting the menu bar app.
- Improved command labels so the main action always says what will happen.
- Made clipboard, emoji, quicklink, and uninstall screens behave more consistently.
- Made each feature more independent, reducing the chance that one change breaks another.
- Reorganized the project by feature so future additions and contributions are easier to follow.
- Simplified the app’s internal wiring for more reliable shortcuts, extensions, and window actions.

## [0.2.0]

### Added

- Added Sparkle updates with optional automatic checks and background installation.

### Improved

- Revised Settings with clearer pages, controls, shortcuts, and denser lists.
- Refreshed About with project, contact, and update links.
- Improved keyboard selection across calculator results, sections, and empty result sets.
- Improved launcher responsiveness during repeated searches and refreshes.
- Improved launcher refreshes by reusing unchanged app metadata.
- Improved hotkey settings and paste reliability.
- Improved hotkey reliability when another app is using the same shortcut.
- Improved shutdown cleanup for extension commands.
- Improved launch-at-login setup when macOS rejects a change.
- Improved reliability when saving snippets and quicklinks.
- Improved clipboard selection and action consistency.
- Improved separation between installed and development app data.
- Improved uninstall responsiveness for applications with many files.
- Improved confirmation flows and reliability of hotkeys and snippets.

### Fixed

- Fixed some applications opening without coming to the front.
- Fixed updates not installing by replacing the previous update flow with Sparkle.

## [0.1.6]

### Added

- Added the `Import Extension` command for installing local trusted `.ocx` packages without Store publishing.
- Added shared row navigation shortcuts: Option+Arrow jumps five rows, and Command+Arrow jumps to the first or last row across palette lists.
- Added persistent pin actions for snippets and quicklinks, including `⌘P` and pinned-first search ordering.

### Fixed

- Fixed declared shell extension commands so shell source is executed correctly instead of being treated as a literal executable name.
- Fixed Store updates for extensions installed with an older package contract.
- Routed update installer failures through the shared confirmation dialog system.
- Fixed extension confirmations so the palette stays open while actions are confirmed.
- Fixed launcher scrolling to quicklinks when keyboard selection reaches the end of the list.

## [0.1.5]

### Added

- Independent GitHub Release publishing for verified extension packages.
- Added the Store command with palette-based extension browsing, install, update, and uninstall flows.
- Added the `opencast.json` compatibility contract, Raycast API shims, native capability broker,
  filesystem/network/browser/application bridges, and short-lived JavaScriptCore hosts.

### Improved

- Store access and background extension refresh are enabled automatically.
- Added Store sorting by installed status or name.
- Capability and scope hashes now pin Store packages. Every extension install and update is manual,
  and a capability-widening update is never applied by catalog refresh.

### Fixed

- Removed uninstalled extension commands from the launcher after refresh.
- Extension screens now show the active extension name in the footer.

## [0.1.4]

### Added

- Added the JavaScriptCore extension host and native capability bridge without bundling Node, Bun, or an extension runtime.
- Added v1 extension packages for Kill Process, Ports, and System Monitor.
- Added local `.ocx` validation, atomic install, disable, rollback, removal, and static GitHub Release catalog tooling.
- Added shared `PaletteRow` geometry and interaction styling across launcher, clipboard, snippets, quicklinks, uninstall, and extension lists.

### Improved

- Added native process, listening-port, system-metrics, cancellation, and bounded process-job providers for extension commands.
- Added Raycast-shaped list, detail, form, action, dropdown, preference, and menu-bar compatibility surfaces.

### Fixed

- Fixed the self-update flow so downloads complete reliably and the install confirmation appears as expected.

## [0.1.3]

### Added

- Caffeinate, Decaffeinate, and timed Caffeinate For launcher commands.

### Improved

- Quicklinks can now be added to and removed from launcher favorites.
- Palette-level command shortcuts now handle Settings, close, and return-to-root actions reliably.
- Refined the palette surface, footer controls, action keycaps, row spacing, and dark-only styling.
- Settings navigation now scrolls independently from the selected pane.

### Fixed

- Prevented Actions menus from showing the underlying palette rows on older macOS versions.
- Removed the leftover top spacing after removing the Settings sidebar search field.

### Removed

- Removed the light appearance option. Opencast now uses the dark appearance only.
- Removed the Settings-wide search field and search results view.

## [0.1.2]

### Added

- Quicklinks support.
- Reusable inline argument inputs for extension commands.

### Improved

- Hotkeys now support double-tapping command, option, or control modifiers.
- Launcher search now finds renamed applications by previous names retained in macOS metadata.
- Added duplicate actions for snippets and quicklinks.
- Added paste-target application icons to snippet actions.

### Fixed

- Creating a snippet or quicklink now returns to the previous palette screen with success feedback.

## [0.1.1]

### Added

- Snippet support with search, create, edit, and optional keyword expansion.
- Self-update flow for direct installations.

## [0.1.0]

### Added

### Fixed

### Improved

### Removed
