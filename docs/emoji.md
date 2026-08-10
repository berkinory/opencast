# Emoji picker

A palette sub-screen (reached like Clipboard) presenting a searchable emoji grid.

## Layout

- `Features/Emoji/` — the emoji catalog, index, frequency store, and grid adapter:
  - `EmojiCatalog.swift` — the catalog model (groups, names, keywords).
  - `EmojiData.generated.swift` — the emoji dataset.
  - `EmojiIndex.swift` — search index over the catalog.
  - `FrequentEmojiStore.swift` — persisted most-recently / frequently used emoji.
- `Features/Emoji/EmojiGridView.swift` — the SwiftUI grid view.

## Invariants

- **`EmojiData.generated.swift` is emitted by `node Tools/gen-emoji.js`** (Node 18+ for global
  `fetch`) — **never edit it by hand**. Regenerate and commit instead.
- **`EmojiCatalog.swift` must stay AppKit/SwiftUI-free**, because the
  `Tools/emoji-test.swift` harness compiles the real sources:

  ```sh
  swiftc Opencast/Features/Emoji/EmojiCatalog.swift Opencast/Features/Emoji/EmojiData.generated.swift \
    Tools/emoji-test.swift -o /tmp/emoji-test && /tmp/emoji-test
  ```

- Emoji and extension grids use the shared row-based `PaletteGridLayout`; its navigation math stays
  Foundation-free and is covered by `Tools/palette-grid-test.swift`.
