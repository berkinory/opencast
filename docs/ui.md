# UI & Design System

The design system for Opencast's UI, written so an agent restyling or extending it stays consistent
with what's already there. This documents **Opencast as built** — every rule here maps to code in
`Opencast/`. `DesignSystem/Theme.swift` is the single design-token source.

Read this before touching any view body, `Theme` value, or the panel chrome.

---

## The look, in one paragraph

Opencast is a **Raycast-style dark-first command palette**: a borderless floating panel whose surface is
just the OS behind-window blur under an adaptive dark surface — there is no gray chrome. Everything on that
surface uses an appearance-aware neutral ramp. The header and bottom bar **float over the list as fully
transparent overlays**; there are no hard-edged bars, strips, or dividers. Rows don't clip under the
bars, they **dissolve**: a scroll-driven gradient mask ghosts them as they pass beneath. Popover menus use **Liquid Glass on macOS 26+**; footer controls use a stable appearance-aware neutral surface so their contrast does not shift with wallpaper.
and an opaque dark fallback on older supported systems. The app always uses its dark appearance.

Five load-bearing ideas, in priority order:

1. **Surface = adaptive dark surface over HUD blur.** No gray chrome. The desktop adds texture without washing out the dark surface.
2. **Appearance-aware neutral ramp, never grays.** Text and surfaces use the selected content/surface base at fixed stops.
3. **Floating bars, not chrome.** Header/footer are transparent overlays; the list fills the whole panel.
4. **Edges dissolve, they don't clip.** Scroll-driven mask, no separators between list and bars.
5. **Glass only on floating controls.** The main surface is never glass; pills/menus/circles are.

---

## Non-negotiable invariants

These are the things that quietly break the look if changed. Preserve them unless the task is explicitly to change them.

- **Dark only.** `AppCore` applies the dark appearance globally. Theme tokens keep their neutral ramp for system color resolution, while brand accents remain fixed.
- **No grays, no opaque fills on the surface.** Reach for `Theme.Colors.*` (appearance-aware neutral alpha) instead of `.gray`, `NSColor.windowBackground`, etc.
- **No hard dividers between the list and the bars.** The header and bottom bar are `safeAreaInset` overlays with no background; separation comes from `edgeDissolve()`, nothing else. (One deliberate exception: the vertical hairline between the clipboard list and its preview pane.)
- **The panel corner is clipped once, at the root.** `RootPaletteView.body` ends with `.background(adaptive panel surface) → .background(VisualEffectView(.hudWindow)) → .overlay(stroke) → .clipShape(RoundedRectangle(26, .continuous))`. Keep that order; the surface goes _over_ the vibrancy, and the clip is last.
- **Don't use the native scroll edge effect.** Inside a transparent panel it renders a hard-bounded rectangle. Use `edgeDissolve()`.
- **Test over a light desktop.** Transparency and corner masking bugs only show over bright wallpaper. Dark wallpaper hides them.

---

## Tokens — `Opencast/DesignSystem/Theme.swift`

`Theme` is the single source of truth. **Never hardcode a spacing/radius/size/color that has a token.**
Add a token rather than a magic number when introducing a new value.

### Spacing (`Theme.Spacing`)

`xxs 2` · `xs 4` · `sm 6` · `md 8` · `lg 10` · `xl 12` · `xxl 20` · `rowVertical 7`

`xxs` is the tight gap between adjacent keycap chips (used everywhere keycaps sit side by side).

Row content insets are `md` horizontal and `rowVertical` vertical; list horizontal inset is `md`; the search icon aligns with rows via `md * 2`.

Section-header rhythm has two dedicated tokens: `sectionHeaderBottom` (header → first row) and
`sectionSpacing` (gap above every header **except the list's first**, which reads as the previous
section's closing padding). See "Section headers" below.

### Radius (`Theme.Radius`)

`panel 26` · `row 10` · `card 10` · `menuPanel 16` · `menu 6` · `menuRow 10` · `thumbnail 6` · `keyCap 6` · `recorderKeyCap 4`

`menu` is the shared small-control corner (sidebar tiles, About link pills); `menuRow` is the slightly rounder hover highlight behind popover-menu rows.

Always `RoundedRectangle(cornerRadius:, style: .continuous)` — continuous corners everywhere, never `.circular`.

### Size (`Theme.Size`)

`panelWidth 750` · `panelHeight 475` · `headerHeight 44` · `bottomBarHeight 52` · `rowIcon 24` ·
`keyCap 18` · `recorderKeyCap 16` · `menuButton 36` · `feedbackToast max 420` ·
`clipboardListWidth 290` · `menuWidth 276` · `menuIcon 20`

Settings metrics live in the nested `Theme.Settings` namespace so changing its compact fixed-window UI cannot drift the palette: window `760×560`, sidebar `200`, header icon `38`, row icon `28`, and control height `32`.

`keyCap` sizes the palette's keycap chips; `recorderKeyCap` (both size and radius) is the intentionally-smaller Settings shortcut-recorder chip.

### Typography (`Theme.Typography`)

System fonts only — **no fixed point sizes in views** (honors Dynamic Type). `searchField` is the one
explicit size (18pt regular). Use `rowTitle` (`.body`), `sectionHeader` (`.subheadline.medium`),
`rowTrailing`/`bar`/`menuRow`/`keyCap` etc. as named.

### Colors (`Theme.Colors`) — the appearance-aware neutral ramp

| Token            | Value          | Use                                              |
| ---------------- | -------------- | ------------------------------------------------ |
| `panelSurface`   | dark `#131313` / light `#f5f5f5` | adaptive panel surface over vibrancy |
| `panelStroke`    | content base 0.08 | subtle outer edge                            |
| `footerSurface`   | dark `#292929` / light `#fcfcfc` | footer action and mode controls              |
| `footerStroke`    | content base 0.16 | footer control outline                      |
| `selection`      | content base 0.12 | selected row fill (keyboard/active selection) |
| `rowHover`       | content base 0.05 | mouse-hover fill (always fainter than selection) |
| `menuHover`      | content base 0.10 | popover-menu row hover                        |
| `separator`      | content base 0.10 | the clipboard list↔preview hairline          |
| `controlSurface` | content base 0.14 | filled keycaps, glyph tiles                   |
| `border`         | content base 0.20 | outlined keycap borders                       |
| `textSecondary`  | content base 0.60 | secondary labels                              |
| `textTertiary`   | content base 0.40 | placeholders and low-priority metadata        |
| `rowSecondary`   | content base 0.56 | row subtitles and keywords                    |
| `rowKind`        | content base 0.52 | trailing row kind labels                      |
| `sectionHeader`  | content base 0.58 | list section headers                          |
| `cardFill`       | content base 0.05 | settings/calc card fill                       |
| `cardStroke`     | content base 0.10 | settings/calc card border + inset dividers    |
| `glassFrost`     | content base 0.10 | appearance-aware tint layered into glass      |

Beyond these, `.secondary`/`.tertiary` foreground styles are fine for SF Symbols (they resolve against
the dark surface). **Selection always beats hover** when a row is both.

---

## Panel structure — `Features/Palette/PalettePanel.swift`, `Features/Palette/RootPaletteView.swift`

- **`PalettePanel`** is a borderless `NSPanel`: `isOpaque = false`, `backgroundColor = .clear`, `.floating` level, `hasShadow`, `animationBehavior = .none`. It hosts SwiftUI via `NSHostingView`. `PaletteWindowController` centers it slightly above screen center (`+8%`) and dismisses it on `windowDidResignKey`.
- **The results layer fills the whole panel.** The header and bottom bar attach via `.safeAreaInset(edge: .top/.bottom)` as transparent overlays that float _over_ the list. The list underlaps them and dissolves at the edges.
- **Header** (`headerHeight 44`): a back-chevron _or_ mode glyph, then the plain `TextField` (no border/background). Clipboard and Emoji show the back chevron; the launcher shows a magnifying glass. The search icon aligns horizontally with row content.
- **Compact keyboard entry:** pressing `↓` in the collapsed launcher expands the results and selects the first row without replacing or defocusing the shared search field.
- **Bottom bar** (`bottomBarHeight 52`): the launcher has a menu circle on the left; sub-screens replace it with a floating mode pill showing their icon and title. Both open the same About / Settings menu. The action group stays on the right — all controls use the same appearance-aware footer surface, with no bar background. The action group is one `Capsule` holding the primary-action pill (label + `↵`) and the Actions toggle (`⌘K`).
- **Feedback**: `PaletteFeedbackButton` is the compact footer-only state. `FeedbackToastView` is the shared capsule/glass presentation for extension toasts and the screen-level HUD; `ToastWindowController` places the HUD at the active screen's bottom center so it survives palette dismissal.

---

## The edge dissolve — `DesignSystem/EdgeDissolve.swift`

The signature effect. A scroll-driven `LinearGradient` mask on each list so rows soften as they approach
a floating bar, ghost beneath it, and vanish only at the window edge. Attach with `.edgeDissolve()` on
the `ScrollView`, **before `.thinScrollbar()`** (so the scrollbar overlay stays unmasked).

- Fade bands: top = `headerHeight + headerPadding + 32`, bottom = `bottomBarHeight + 28` — each overshoots its bar into the visible list, so the ramp finishes ~32/28px _past_ the bar rather than cliffing at its edge.
- Alpha floors mid-scroll (not to 0): **top 0.15, bottom 0.25**, eased by how much content is hidden past the edge (`1 − (1 − floor)·clamp(dist/band, 0, 1)`).
- Only masks when the list is scrollable; the edge stop stays transparent so rubber-band bounces still dissolve. A list that fits gets no mask.
- The mask spans the scroll view's **full** frame (`.ignoresSafeArea()`) — otherwise the bars' safe-area insets shift the gradient onto at-rest rows.

---

## Rows, selection, hover — `Features/PaletteRow.swift`

All standard palette lists use the shared `PaletteRow` shell so launcher, clipboard, snippets,
quicklinks, uninstall and extensions keep the same geometry:

- `HStack(spacing: lg)`: leading 24pt icon/thumbnail, title (`.body`, `lineLimit(1)`), optional trailing keycaps/kind label, `Spacer`. Insets: `.horizontal md`, `.vertical rowVertical`.
- Background is a `RoundedRectangle(row, .continuous)` filled by `PaletteRow`: **selection → hover → clear**, in that precedence. Card and grid views keep their own surfaces because they are not standard list rows.
- **Hover state lives in `PaletteRow`**, not the list, so a mouse sweep repaints only the rows entering/leaving (a list-level hover rebuilds every row per move — don't do that).
- **Scroll follows explicit intent only**, driven by a cancellable `ListScrollIntent` — mouse selection never yanks scroll and keyboard navigation minimally reveals rows. Top intents reset the backing clip view to the exact inset-aware origin, including after compact mode expands.
- **Keycaps** use `KeyCapChip`: `.outline` (white-0.20 border) for hotkey hints on rows, `.filled` (white-0.10 fill) for footer shortcuts.

### Section headers

The palette lists (App Launcher, Clipboard, Emoji) render category labels
through one shared **`SectionHeader`** (`.subheadline.medium`, secondary — `Features/Launcher/LauncherView.swift`).
The launcher shows a single "Results" header over search matches, and per-kind sections
(Favorites / Applications / System Settings / Commands) for the empty query; clipboard/history use
date buckets (Today / Yesterday / …), and the clipboard adds a "Pinned" section above them holding
every pinned entry (filtered searches included).

Spacing lives in `Theme.Spacing`: `sectionHeaderBottom` (header → first row) and `sectionSpacing`
(gap above every header **except the list's first**, which reads as the previous section's closing
padding). Each list passes `isFirst: row.id == <rows>.first?.id` so only the very first row skips the
leading gap. Headers are non-selectable display rows, so selection (keyed by id) is unaffected.

---

## Liquid Glass — `Theme.frosted(in:)`, `Features/PopoverMenu.swift`

Glass is **only** for floating controls, never the main surface.

- `View.frosted(in:)` uses `glassEffect(.regular.interactive().tint(glassFrost), in:)` + `.tint(.clear)` on macOS 26+, and an opaque dark surface with a border below it on older systems. Used by popover menus; footer controls use `paletteFooterSurface(in:)`.
- **Menus are in-window overlays, not system popovers.** `.contextMenu`/`NSMenu` stall clicks for seconds inside a `LazyVStack` and spill outside the panel. Use `PopoverMenu` anchored to a bottom corner via `.overlay`, inset `menuInset` (8pt) so its own corner isn't clipped by the panel's.
- **`PopoverMenu`** uses the same `frosted` surface with **no hand-tuned shadow** — Tahoe glass carries its own elevation, while the older-system fallback is opaque so rows behind an open menu cannot bleed through.
- `PopoverMenuRow`: leading glyph, label, trailing shortcut glyph, `menuHover` fill on hover, `menuRow 10` corner. Menus animate in with `.opacity + .scale(0.96)` from the anchored corner, `easeOut 0.14`.
- The glyph is a `PopoverMenuIcon`: `.symbol` uses the shared `FeatureIcon` tile (primary — or **red** when `isDestructive`) and `.file` uses a real app icon via `IconCache` for paste targets. `PopoverMenuItem` keeps a `systemImage:` convenience init, so symbol rows read exactly as before.
- **Both glyph kinds share one square `menuIcon` (20) slot**, which pins one row height. `FeatureIcon` owns the system glass/tile treatment for symbols; `IconCache` supplies the platform app icon for file-backed rows.
- Menu rows are the one place that uses `sm` for the icon→label gap instead of the row-standard `lg`, because that slot's built-in slack already contributes 2–3pt of apparent space.

---

## Scrollbars — `DesignSystem/ThinScrollbar.swift`

Custom thin overlay scrollbar (the native one flashes and reserves a gutter inside a transparent panel).
`.hideNativeScrollers()` on the scroll _content_ forces the backing `NSScrollView` to a hidden `.overlay`
style; `.thinScrollbar()` on the scroll view draws a hairline thumb (`Color.primary` alpha 0.30 rest →
0.42 hover → 0.5 drag) that fattens on hover, with a faint rail revealed only while hovering/dragging.

Routing: the palette lists (App Launcher, Clipboard history, Emoji, Calculator history) use
`.thinScrollbar()` + `.hideNativeScrollers()`; the Clipboard preview (right pane) and every Settings
pane use the native `.overlayScroller()`. Don't reintroduce native scrollers on the palette lists.

---

## Settings — `Features/Settings/SettingsComponents.swift`

Settings runs in a fixed `860×620` `NSWindow` (the SwiftUI `Settings` scene is unreliable for accessory apps) and uses the palette's own surface language: behind-window blur under the same dark scrim, the same neutral ramp, and the same row/keycap grammar. Preferences contains General, Launcher, and Commands. Each optional feature has its own page under Features: Clipboard, Snippets, Quicklinks, Emoji, Calculator, and Window Management. About remains separate. Applications and System Settings live under Launcher, while each shortcut lives beside the feature or command it controls.

- **Sidebar** uses plain monochrome SF Symbols in fixed slots instead of icon tiles. A selected row gets one neutral fill and a short accent rail; section labels provide the hierarchy without turning every item into a separate visual card. Other Settings scrollers disable AppKit elasticity.
- **`SettingsPane`** owns scrolling, destination jumps, fixed insets, and a `SettingsFeatureHeader`: a large title and readable subtitle with one quiet trailing identity symbol.
- **`SettingsSection`** pairs a small section symbol, title, and explanatory caption with controls on the palette's `cardFill`/`cardStroke` surface. `SettingsRowDivider` aligns below the row title, past any optional row symbol.
- **`FeatureIcon`** remains the shared identity renderer for palette features, shortcut targets, and in-window menu symbols. Synthetic launcher commands use the quieter neutral `CommandIcon` surface so they do not compete with real application icons.
- **`SettingsControlRow`** prioritizes title, caption, and intrinsic-width trailing control. Row symbols are optional and unframed; identity belongs at pane and section level instead of repeating on every setting.
- **`SettingsStatusCard`** keeps a neutral card surface and uses semantic color only on its status glyph.
- Feature controls do not have to collapse into rows: Launcher uses visual Standard/Compact tiles, Search Locations uses compact removable rows, Clipboard and Snippets share one application-exclusion editor, Emoji uses direct tone swatches, and per-item shortcuts use an aligned table. Their selection surfaces stay neutral.
- Boolean settings use compact switches. Checkboxes are reserved for multi-selection tasks, not persistent preferences.
- Optional feature pages start with one compact, single-line feature switch without a section header. Disabled features also disable their nested controls and remove their launcher commands. Window and feature command rows keep shortcut and launcher visibility controls together.
- Launcher-item and command lists use the page scroller and the same compact row grammar as window commands; never put them in a second fixed-height scroll table.
- About uses a centered icon hero, three direct-link tiles, and one compact update bar. It has no generic settings sections, pinned footer, or secondary status card.
- `ShortcutRecorder` follows the Raycast-style two-layer model: its fixed monochrome trigger always shows a neutral border around `Record Hotkey` or one combined glyph value, and a bound shortcut shows its clear `×` whenever it is idle, without changing the footprint; capture hides the clear segment and releases its reserved content space. Recording opens an instant anchored capture popover above the field with modifier preview and a target footer whose icon matches the target row. Conflict feedback resolves on the next key press; success enters quickly, then fades into the neutral editing state. Feedback color animates independently while foreground content always changes immediately. Space or Return starts capture, Escape closes it, and Delete clears the binding.
- Custom Settings controls use the shared neutral `settingsFocusRing` modifier so they remain visible and operable in the full keyboard-access loop.
- Settings navigation, hover, shortcut capture, and destination scrolling update immediately. The only deliberate animation is the short destination highlight fade; do not add springs or slow pane transitions.

The calculator's inline `CalculatorCard` reuses this card language (`cardFill` + `cardStroke`) rather than the row language, since it's a highlighted answer, not a list item. A value answer is a **two-column** layout: a source column (input echo) and a target column (result), separated by a centered `arrow.right` glyph (no divider line). Each column optionally carries a word-name **badge pill** beneath its value (`keyCap` font, `controlSurface` fill, `keyCap` radius) — the unit long names for a conversion (`Meters`→`Feet`), or the moment labels for a date/time calc (`12:18 AM`→`9:00 AM`, `Friday, 24 July`→`Friday, 9 April, 2027`). Plain arithmetic leaves both badges nil, so the card stays a clean value → value line.

---

## Rules for agents working on the UI

- **Restyle from screenshots, not extracted CSS.** Pixel-matching Raycast from its bundle led to wrong results before; compare rendered screenshots over a light desktop instead. There's no screen-recording from the shell here — verify AppKit rendering with a `swiftc` harness that prints layer state, and let the user do visual sign-off.
- **Don't add behavior that wasn't requested.** A restyle changes appearance, not interaction — keep selection/scroll/dismiss/focus flows exactly as they are unless the task is about them.
- **New tokens go in `Theme`**, referenced everywhere. No magic numbers in views.
- **Keep the shared grammar shared.** If you change row insets, the `fill` precedence, section-header style, or keycap style, change it for _all_ lists — divergence is the bug, not the feature.
- **Build & verify** with the real toolchain (see [`development.md`](development.md)); a design change that doesn't compile under Swift 6 mode isn't done.
