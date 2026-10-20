# Changelog

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
