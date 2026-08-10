# UI

Opencast uses one keyboard-first visual system across the palette, settings, auxiliary windows, and
extension surfaces. The interface should feel native to macOS, dense enough for fast scanning, and
clear without decorative structure.

## Source of truth

`Opencast/DesignSystem/Theme.swift` owns spacing, size, radius, typography, color, and motion tokens.
Shared AppKit and SwiftUI primitives live in `Opencast/DesignSystem/`; reusable palette components
live in `Opencast/Features/Palette/`.

Use existing tokens and components before adding a local value. Add a token only when a measurement
is reused or represents a stable system rule. Feature-specific geometry may stay near the feature.

Neutral colors must resolve from the current appearance. Brand colors and semantic status colors may
remain fixed. The app uses a dark appearance today, but shared surfaces must not assume raw black or
white values.

## Palette

The palette is a fixed-width AppKit panel with a shared search header, content region, and footer.
It can open as a compact search bar and expand downward without moving its top edge.

Keep these invariants:

- `PaletteWindowController` owns window size and placement; SwiftUI never drives the frame.
- One search field remains mounted across compact and expanded states.
- A flat selection index follows the exact visible order, including inline results.
- Keyboard navigation changes selection and scrolls only enough to reveal it.
- Pointer hover does not steal keyboard selection or force scrolling.
- Opening an actions menu freezes input without moving first responder.
- Escape closes the deepest active layer before dismissing the palette.
- Paste and activation restore the previously focused app when required.

Use `PaletteListLayout` for vertical results and `PaletteGridLayout` for sectioned grids. Use shared
row, section header, detail, action, footer, scrollbar, edge dissolve, and right-click components.
Built-in features and extensions should receive the same selection, hover, activation, scrolling,
and action behavior.

## Rows and actions

Rows have one clear primary label. Secondary text describes the item; trailing content communicates
state, metadata, or a shortcut. Do not repeat the same label in multiple columns or add a card around
every row.

Selected and hovered states are separate. Selection follows the keyboard; hover follows the pointer.
Primary activation uses Return, secondary actions live in the shared actions menu, and destructive
actions require clear naming and the established confirmation flow.

Use SF Symbols unless a real application, service, or file icon improves recognition. Match optical
size rather than assigning the same numeric frame to artwork with different bounds.

## Settings

Settings uses a sidebar for stable categories and grouped rows inside each pane. Keep one level of
hierarchy inside a pane: section, row, control. Avoid nested cards, repeated availability labels, and
explanatory text that restates a control.

Feature enablement is a single-line parent toggle. Dependent controls remain visible but disabled
when the feature is off. Put each global shortcut beside the feature or command it controls rather
than in a separate shortcut inventory.

Use shared settings rows, dividers, toggles, pickers, shortcut recorders, headers, and focus rings.
All custom controls must work with Full Keyboard Access and expose a useful accessibility label.

## Motion and feedback

Motion explains state changes; it must not decorate idle content. Keep transitions short, preserve
spatial continuity, and avoid animating layout properties that move the search field or selected row.
Respect Reduce Motion where an effect is not required for comprehension.

Use the shared HUD for brief completion feedback and native dialogs for decisions or errors. A toast
must not take focus. Error text should state what failed and what the user can do next.

## Review checklist

- Check keyboard-only operation, including Full Keyboard Access.
- Check pointer hover, right-click, double-click, and scroll behavior.
- Check empty, loading, disabled, error, and long-content states.
- Check the oldest supported macOS appearance and the current macOS appearance.
- Check compact-to-expanded geometry and repeated open/close focus restoration.
- Compare screenshots at the same window size and desktop background.
- Run `make lint`, the relevant harness, and `make build`.
