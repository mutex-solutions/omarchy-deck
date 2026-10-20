# Changelog

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
