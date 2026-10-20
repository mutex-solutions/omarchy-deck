# Staying in sync with Omarchy

Deck sections add their own presentation. They should not own behaviour that
Omarchy already implements, because a copy of that behaviour is a fork: when
Omarchy fixes or extends it, the copy silently stays behind.

This document is the rule for every section: **reference upstream at runtime,
never copy it.** There are three usable seams and one that is not.

## 1. CLI helpers (`omarchy-*`)

The stock panels are thin front ends over stable command contracts. Call the
same commands:

| Feature | Helper |
| --- | --- |
| Bluetooth power and devices | `omarchy-bluetooth-power`, `omarchy-bluetooth-device` |
| Audio routing to a connected headset | `omarchy-audio-output-set-default` |
| Per-monitor brightness (backlight, Apple, DDC) | `omarchy-brightness-display --monitor` |
| Monitor scale | `omarchy-hyprland-monitor-scaling` |
| Desktop text size | `omarchy-display-text-size` |
| Network details and band | `omarchy-network-status`, `omarchy-network-band` |
| Tailscale actions | `tailscale` itself |

Omarchy updates these in place, so the section inherits the fix without a
change here. Pairing sequence, trust handling, DDC quirks and scale cleaning
all live behind them.

## 2. Quickshell modules

Live device state comes from the same modules the stock panels use:

- `Quickshell.Networking` for Wi-Fi scanning, `connect`, `connectWithPsk`,
  `disconnect`, `wifiEnabled`
- `Quickshell.Bluetooth` for the adapter and device list
- `Quickshell.Services.Pipewire` for sinks and the preferred default

These ship with Omarchy's shell, so protocol and API changes are inherited the
same way as the helpers.

## 3. Upstream service QML, loaded by URL

Some logic exists only in QML. The Tailscale panel keeps it in a `Service.qml`
component, not behind a helper. A third-party plugin cannot import it, but a
`Loader` can instantiate the installed file directly:

```qml
Loader {
  id: tailscaleUpstream
  source: "file:///usr/share/omarchy/shell/plugins/panels/tailscale/Service.qml"
}

readonly property var tailscaleService: tailscaleUpstream.item
```

The loaded item exposes the same API the stock panel uses
(`toggleTailscale()`, `active`, `statusText`, `peers`, `exitNodes`,
`accounts`, `refresh()`). Nothing is copied, so an Omarchy update to that file
reaches the section on the next shell start.

This is the pattern for any future upstream `Service.qml`. Always keep a
helper/CLI fallback for when the file is missing or a member disappears.

Use it for **state and actions**, not for the panel's layout. The stock
panel's `Panel.qml` is a popup `Panel` with no embeddable content component.

## 4. The stock panel UI: not embeddable

The stock panels are `Panel` windows. They cannot be placed inside a Deck
page, and copying their QML would freeze a snapshot. Two choices:

- **Render the UI here** from seams 1–3. This is what the sections do. The
  layout is Deck's, the behaviour is upstream's.
- **Summon the stock panel** through Deck's registry (`stockPanel`), which
  opens Omarchy's own popup. It updates perfectly, but it is a separate
  popover, not a Deck page.

`docs/CONTRACT.md` describes the page contract; this document says where the
data behind a page should come from.

## Compatibility check

The file paths and helper names above are internal to Omarchy. Run
`scripts/check-upstream.sh` after an Omarchy update: it verifies every helper
used by the sections and the Tailscale service file and its expected members.
A failure means a seam moved; fix the reference or use the fallback, do not
copy the feature.
