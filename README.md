# Deck

A pluggable control surface for the Omarchy bar. One icon opens a panel of
tiles; **click toggles, hold opens that tile's page.**

Deck is an Omarchy **plugin**. What it hosts are **sections**: plain QML
components listed in `sections.json`. A section is not a plugin. It has no
manifest, Omarchy never discovers it, and only Deck reads it. The full interface
is in [`docs/CONTRACT.md`](docs/CONTRACT.md).

**Status: barebone.** This repository is the host and the contract only. It
ships one example section so the panel is not empty; the real sections (audio,
Bluetooth, Wi-Fi, display) are not here yet.

## Install

```bash
omarchy plugin add https://github.com/mutex-solutions/omarchy-deck --enable
```

The panel appears in the bar as `▦`. With only the example section it looks like
a single tile. That is expected.

## The contract in one screen

A section is a directory entry in `sections.json` plus a QML component:

```
sections.json          one line per section
sections/<id>.qml      state + tile face      (required)
sections/<id>-page.qml detail view            (optional)
```

**`sections/<id>.qml`** must expose:

| Member | Type | Meaning |
|---|---|---|
| `active` | `bool` | on/off; drives the tile's colour |
| `label` | `string` | tile title |
| `detail` | `string` | tile second line |
| `icon` | `string` | glyph |
| `toggle()` | function | what a click does |

**`sections/<id>-page.qml`** receives:

| Member | Type | Meaning |
|---|---|---|
| `section` | `var` | the live section instance; the page reads state from here |
| `host` | `var` | `{ close(), notify(text) }` |

Deck draws the back button, the title and the frame. A page that draws its own
back button is a contract violation.

**State lives in the section, never in the page.** The page is handed the same
instance the tile uses, so the two cannot disagree about whether something is on.
Anything that must survive closing the page belongs in the section.

Full rationale, gestures and lifecycle: [`docs/CONTRACT.md`](docs/CONTRACT.md).

## Adding a section

1. Copy `sections/example.qml` and change the five members.
2. Optional: copy `sections/example-page.qml` for a detail view.
3. Add an entry to `sections.json`.
4. `omarchy restart shell`.

The host does not change. If adding a section ever requires editing `qml/`, the
contract is wrong. That is the property this repo exists to protect.

## What the host does and does not do

**Does:** the popup, the grid (half-width and full-row tiles), click-vs-hold,
page swap and back, theme via `qs.Commons` (`Style`, `Color`, `Util`), error
isolation per loader.

**Does not:** know anything about what a section controls, cache section state,
isolate sections from each other (one QML engine), or discover sections
automatically. The registry is explicit, so a half-written section cannot appear.

## Requirements

- Omarchy 4.x (Quickshell shell)

## Licence

MIT. See [LICENSE](LICENSE).
