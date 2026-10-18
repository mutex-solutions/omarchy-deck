# Deck section contract v1

The host (Panel.qml) lays out tiles, owns gestures, and swaps pages. It never
imports a system service. Everything it knows comes from the section.

## A section is a directory

```
sections/<id>/
  section.json     placement + behaviour (data)
  Section.qml      state + tile face (required)
  Page.qml         detail view (optional)
```

## 1. `section.json` — placement and behaviour

| Key | Type | Default | Meaning |
|---|---|---|---|
| `id` | string | required | unique; also the IPC name |
| `title` | string | `id` | page header |
| `icon` | string | `"•"` | fallback glyph if the section does not supply one |
| `order` | int | 100 | sort position; ties break by id |
| `size` | `{w,h}` | `{w:2,h:1}` | grid units; grid is 4 columns wide |
| `toggleable` | bool | `true` | see gestures below |
| `hold` | `"page" \| "none"` | `"page"` | whether a hold opens a page |
| `page` | string | — | required when `hold` is `"page"` |
| `hidden` | bool | `false` | leave it out of the grid |

Config (`~/.config/deck/config.json`) may override `order`, `size`, `hidden`
and `accent`. Precedence is **section.json defaults < config.json**, and the
merged result is what the host uses. The section can never read config itself —
that keeps one parser (the helper) and one precedence rule.

## 2. `Section.qml` — state lives here, and only here

Required:

| Member | Type | Meaning |
|---|---|---|
| `active` | `bool` | on/off. Drives the tile's accent colour. |
| `label` | `string` | tile title line |
| `detail` | `string` | tile second line |
| `icon` | `string` | glyph |
| `toggle()` | function | what a click does when `toggleable` |

Optional:

| Member | Type | Meaning |
|---|---|---|
| `busy` | `bool` | dims the tile and swallows input while an action settles |
| `customTile` | `Component` | replaces the default icon+label+detail body |
| `actions` | `list<{id,title,icon}>` | extra verbs exposed to IPC/keybinds |

**The section is the single source of truth.** The tile and its page read the
same instance — the page is handed `section`, it does not create a second copy.
That is what makes "tile shows on, page shows the list" impossible to desync.

## 3. `Page.qml` — detail view

| Member | Type | Meaning |
|---|---|---|
| `section` | `var` | injected: the live Section instance |
| `host` | `var` | injected: `{ close(), notify(text) }` |

The page renders **content only**. The host draws the back button, the title,
and the frame, and owns the popout lifecycle. A page that draws its own back
button is a contract violation.

## 4. Gestures

| `toggleable` | click | hold |
|---|---|---|
| `true` | `toggle()` | page |
| `false` | page | page |

A hold **never** toggles. A tap renders no hold indicator: the progress hairline
is attached only after 180 ms, so short presses show nothing at all.

## 5. Lifecycle

- Sections load once when the plugin loads and stay mounted, visible or not.
  Local state (a password field, a scroll position) survives closing the panel.
- Pages load when held and are destroyed on back. They must therefore derive
  everything from `section`, not from their own memory.
- A section that fails to load is skipped and logged; it must not take the
  panel or the bar down with it.

## 6. What the host guarantees / does not

Guarantees: theming (`Style`, `Color`), the grid, gestures, page chrome, the
notice strip, error isolation per `Loader`.

Does **not** guarantee: process isolation (a crashing section can take the
panel with it), cross-section messaging (sections must not talk to each other),
or discovery (the registry is explicit — a section is listed, not scanned).

## 7. Page layout conventions

Taken from Apple's actual Wi-Fi and Bluetooth screens (Apple Support's Wi-Fi
status menu; macOS System Settings › Bluetooth), adapted to Deck's dark theme
and to omaudiopanel's row layout — rows, not cards.

**Structure, both pages:**

```
[←]  Title                         [toggle]     header: back, title, master switch
───────────────────────────────────────────
SECTION LABEL                                     small-caps, muted
  ◉  item name                    trailing      one row per item
  ○  item name                    trailing
```

Rules that carry across every page:

- **The master toggle lives in the header**, not as a row. Apple puts Wi-Fi on/off
  and Bluetooth on/off there, and it keeps the list about *choices*, not state.
- **Grouped sections with small-caps labels** (`Known Network`, `Other Networks`,
  `My Devices`, `Nearby Devices`), not one flat list.
- **The connected item is marked by its leading icon**, filled in the accent
  colour — not by a checkmark on the right. The right edge is reserved for
  status (lock, signal, battery).
- **Secondary status sits on the row's second line** (`Connected — 78%`), not as
  another column.
- **Destructive or scanning actions are explicit**: a `Connect` button on a
  nearby device, a spinner while scanning. Never "click anywhere and hope".
- **An empty group says so** — `No devices` — rather than disappearing, so the
  user knows the group is empty rather than missing.
- **A footer action** (`Wi-Fi Settings…`) is the escape hatch to the full system
  UI for the long tail we do not implement.

## 8. Minimal example

```qml
// Section.qml
import QtQuick
import Quickshell
import Quickshell.Networking

Item {
  readonly property bool active: Networking.wifiEnabled
  readonly property string label: "Wi-Fi"
  readonly property string detail: Networking.wifiEnabled ? "on" : "off"
  readonly property string icon: "≋"
  function toggle() { Networking.wifiEnabled = !Networking.wifiEnabled }
}
```
