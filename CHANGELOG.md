# Changelog

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
