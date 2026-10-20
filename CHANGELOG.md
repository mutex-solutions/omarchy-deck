# Changelog

## 0.3.1

- The size page only offers **Remove from the deck** for a section that is
  actually on the deck. An Available section's page is a place to add it.

## 0.3.0

- **Arranging is a page, not a mode on the grid.** Edit opens the Layout page:
  every placed section with a size door and a remove, every available section,
  and the first-party catalogue. The home grid keeps its controls.
- **Full size previews.** The size page renders the real tile at `1×1`, `2×1`,
  `4×1` and `2×2` (custom tiles only) with the live section inside, rather
  than an abstract outline. Choosing a size places the section and returns to
  the deck.
- **`catalog.json`.** The nine first-party sections are preloaded with their
  repository URLs, titles, glyphs and descriptions.
- **Install from GitHub.** Paste a repository URL; `scripts/deck-add-section`
  clones it with `omarchy plugin add`, reads the manifest, requires
  `deck/Section.qml`, and merges one entry into the registry with an atomic
  rename. Already-installed plugins are registered by their git origin instead
  of failing. The registry keeps its order and its span/rows on re-add.
- IPC: `edit`, `choose`, `install`, `status`, `setSize`, `setShown`.
- The grid's content scrolls; the tile overlay and the old size cycle are
  gone.
- **Connectivity is no longer a section.** It was a composite of four radios;
  the catalogue carries Wi-Fi, Bluetooth and Tailscale as individual sections,
  and a user places them in whatever arrangement they want. The connectivity
  plugin still works standalone but is not registered with Deck.

## 0.2.0

- **Arrange mode.** An Edit button in the panel header turns the grid into a
  layout editor: every tile gets a remove `×` and a size chip, and a list under
  the grid offers every section that is not currently shown. Done leaves the
  editor. The panel leaves arrange mode when it closes.
- **Tile sizes.** `1×1` (icon only), `2×1` (half), `4×1` (full) and `2×2`
  (square). A custom tile, such as the connectivity cluster, becomes its icon
  at `1×1`, so the small size means the same thing for every section.
- **`~/.config/deck/layout.json`.** The user's shown/size overrides, kept
  separate from the registry so the bundle and `omarchy plugin update` stay
  clean. The registry's `hidden` flag is now only a default: any registry
  entry can be added from arrange mode.
- **Custom tiles fill their cells.** A 2x2 custom tile is inset by zero and its
  children use the grid's own gap, so the connectivity cluster's four radios
  are the big square rather than four small squares inside one.
- The grid's content scrolls when the editor needs more height.
- IPC: `edit`, `setSize(id, span, rows)` and `setShown(id, shown)`, for a
  keybind or a scripted setup.

## 0.1.7

- The bundle installs and registers **Tailscale** as a hidden section, so the
  connectivity cluster's Tailscale radio can hold into its page without a
  second tile for the same radio.

## 0.1.6

- `host.open`: pages now know whether they are actually on screen. A page is
  loaded once and survives the panel closing, so `Component.onCompleted` is the
  wrong lifetime for anything with a running cost. The audio page's input meter
  is the first caller: it is a real capture stream, and it now stops when the
  panel closes instead of recording behind it.

## 0.1.5

- `Loader.errorString` is a property, not a function. A section that failed to
  load took the deck log down with a TypeError instead of naming the file.
  Both the tile and hidden-section loaders, and the page loader, now read the
  property.

## 0.1.4

- The bundle wires the **Sessions** section, for moving windows, workspaces
  and whole sessions between displays. Window and workspace management moved
  out of the Display page.

## 0.1.3

- **Hidden sections.** A registry entry with `"hidden": true` is instantiated
  and can be opened through `openSection`, but is not drawn as a tile. This is
  what lets the connectivity cluster's hold open Wi-Fi and Bluetooth without
  duplicating those controls in the grid.
- The bundle wires `wifi` and `bluetooth` as hidden sections.

## 0.1.2

- `docs/UPSTREAM.md`: the sync rule for section authors. Reference Omarchy at
  runtime (helpers, Quickshell modules, upstream `Service.qml` loaded by URL);
  never copy behaviour, because a copy is a fork. The stock panel UI cannot be
  embedded; sections render their own UI over upstream state.
- `scripts/check-upstream.sh`: verifies every helper the sections call and the
  Tailscale `Service.qml` members, so a moved seam fails loudly.

## 0.1.1

- The page ScrollBar is hidden. It overlays the right edge of the page content
  and blocked controls there (the Display page's rate chevron and switches).
  The page still scrolls by wheel and touch.

## 0.1.0 (2026-10-18)

Barebone: the host and the contract, no real sections yet.

- `qml/Panel.qml`: the popup, the grid, click-vs-hold, page swap and back.
- `qml/Tile.qml`: one tile: chrome, state colour, gestures, hold indicator.
- `sections.json`: explicit registry, one entry per section.
- One example section and page, to demonstrate the contract and keep the panel
  from rendering empty.
- `docs/CONTRACT.md`: the members, gestures, lifecycle and limits.

Extracted from the `sysadmin` homelab repo, where it was prototyped alongside
Wi-Fi/Bluetooth sections that are not part of this release.
