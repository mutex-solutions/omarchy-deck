# Deck Section Contract v1

Deck is an Omarchy plugin. What it hosts is a **section**.

That distinction matters because both words are already spoken for:

| Term | Means | Owned by |
| --- | --- | --- |
| plugin | a directory with `manifest.json`, discovered by Omarchy | Omarchy |
| section | a QML component listed in Deck's `sections.json` | Deck |

A section is not a plugin. It has no manifest, Omarchy never discovers it, and
it cannot be installed with `omarchy plugin add`. Only Deck reads it.

The host (`qml/Panel.qml`) lays out tiles, owns gestures, and swaps pages. It
never imports a system service. Everything it knows comes from the section.

## The registry

`sections.json`, at the plugin root:

| Key | Type | Default | Meaning |
| --- | --- | --- | --- |
| `id` | string | required | unique within Deck; also the name used by the `toggleSection` IPC call |
| `title` | string | `id` | the page header |
| `file` | string | required | section component; relative to Deck's plugin root, or absolute to load it from another installed plugin |
| `page` | string | none | detail page, same path rules; omit for no page |
| `span` | `1`, `2` or `4` | `2` | grid units across: 1 is a square and renders icon-only, 2 is half width, 4 is a full row |
| `rows` | `1` or `2` | `1` | grid units tall; 2 makes the 2x2 cluster tile |
| `hidden` | bool | `false` | leave it out of the grid |

The registry is explicit. Nothing is scanned, so a half-written section cannot
appear in the panel.

## Section.qml

Required:

| Member | Type | Meaning |
| --- | --- | --- |
| `active` | bool | on or off; drives the tile's accent colour |
| `label` | string | tile title |
| `detail` | string | tile second line |
| `icon` | string | glyph |
| `toggle()` | function | optional: what a click does. **Omit it when the section has no single on/off** (Display arranges several monitors); Deck then treats a click as "open the page", so the gesture is never dead. |
| `tileComponent` | `Component` | optional: a body for every size |
| `tileCompact` | `Component` | optional: the 1x1 body, falling back to `tileComponent` |
| `tileHalf` | `Component` | optional: the 2x1 body, falling back to `tileComponent` |
| `tileFull` | `Component` | optional: the 4x1 body, falling back to `tileComponent` |
| `tileSquare` | `Component` | optional: the 2x2 body, falling back to `tileComponent` |
| `notice` | object | optional: `{ severity: "info" \| "urgent", title, detail }`; Deck draws it in the shared strip |

## Page.qml

| Member | Type | Meaning |
| --- | --- | --- |
| `section` | var | injected: the live section instance |
| `host` | var | injected: `{ open, close(), notify(text) }` |

A custom body owns its own clicks. While the deck is in edit mode the host
gesture sits above it, so the tile can still be dragged and held. A section
with none of the four size components gets Deck's default body: icon, title
and detail, or icon and title at 1x1.

The page renders content only. The host draws the back button, the title, and
the frame. A page that draws its own back button is a contract violation.

`host.open` is whether the page is actually on screen: the panel is open and
the page has not been closed. Anything with a running cost (a capture meter, a
poll, a busy-loop animation) must bind to it rather than to its own existence.
A page is loaded once and kept while the panel opens and closes, so
`Component.onCompleted` alone is the wrong lifetime.

**State lives in the section, never in the page.** The page is handed the same
instance the tile reads, so the two cannot disagree. Anything that must survive
closing the page belongs in the section.

## Gestures

| click | hold |
| --- | --- |
| `toggle()`, or opens the page when the section has no toggle | opens the page, when the registry entry has one |

A hold never toggles. A tap shows no hold indicator: the progress hairline is
attached 180 ms after the press begins, so short presses show nothing at all.

## Lifecycle

- Sections load when the plugin loads and stay mounted. Local state, such as a
  password field or a scroll position, survives closing the panel.
- Pages load when held and are destroyed on back. They derive everything from
  `section`, not from their own memory.
- A section that fails to load is skipped and logged. It must not take the panel
  or the bar down with it.

## What the host guarantees

Theming through `qs.Commons` (`Style`, `Color`, `Util`), the grid, gestures,
page chrome, and error isolation per loader.

## What it does not guarantee

- **Process isolation.** One QML engine, so a crashing section can take the
  panel with it.
- **Cross-section messaging.** Sections must not talk to each other.
- **Discovery.** The registry is explicit: a section is listed, not scanned.

## Page layout conventions

Taken from Apple's Wi-Fi and Bluetooth screens (Apple Support's Wi-Fi status
menu; macOS System Settings, Bluetooth), adapted to Deck's dark theme and to
omaudiopanel's row layout: rows, not cards.

```
[<-]  Title                        [toggle]     header: back, title, master switch
---------------------------------------------
SECTION LABEL                                    small caps, muted
  (*)  item name                   trailing     one row per item
  ( )  item name                   trailing
```

Rules that carry across every page:

- **The master toggle lives in the header**, not as a row. Apple puts Wi-Fi and
  Bluetooth on/off there, and it keeps the list about choices, not state.
- **Grouped sections with small caps labels** (`Known Network`,
  `Other Networks`, `My Devices`, `Nearby Devices`), not one flat list.
- **The connected item is marked by its leading icon**, filled in the accent
  colour. The right edge is reserved for status: lock, signal, battery.
- **Secondary status sits on the row's second line** (`Connected, 78%`), not in
  another column.
- **Actions are explicit**: a `Connect` button on a nearby device, a spinner
  while scanning. Never "click anywhere and hope".
- **An empty group says so** (`No devices`) rather than disappearing, so the
  user knows it is empty rather than missing.
- **A footer action** (`Open Omarchy network settings...`) is the escape hatch to
  the full system UI for the long tail we do not implement.

## Minimal example

```qml
// sections/example.qml
import QtQuick

Item {
  property bool active: false

  readonly property string label: "Example"
  readonly property string detail: active ? "on" : "off"
  readonly property string icon: "◇"

  function toggle() { active = !active }
}
```

Registered in `sections.json`:

```json
{ "id": "example", "title": "Example",
  "file": "sections/example.qml", "page": "sections/example-page.qml", "span": 4 }
```
