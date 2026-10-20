#!/usr/bin/env bash
#
# Verify the Omarchy surfaces Deck sections reference at runtime.
#
# A failure here means an upstream helper or service file moved or changed
# shape. Fix the reference (or fall back); do not copy the feature.
# See docs/UPSTREAM.md.

set -uo pipefail
fail=0

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "missing helper: $1"; fail=1; }
}

for h in \
  omarchy-bluetooth-device \
  omarchy-bluetooth-power \
  omarchy-audio-output-set-default \
  omarchy-brightness-display \
  omarchy-hyprland-monitor-scaling \
  omarchy-display-text-size \
  omarchy-network-status \
  omarchy-network-band
do
  need "$h"
done

svc=/usr/share/omarchy/shell/plugins/panels/tailscale/Service.qml
if [ ! -f "$svc" ]; then
  echo "missing upstream service: $svc"
  fail=1
else
  for m in toggleTailscale loginOrUp down refresh statusText active peers exitNodes accounts; do
    grep -q "$m" "$svc" || { echo "tailscale Service.qml no longer exposes $m"; fail=1; }
  done
fi

for p in network bluetooth tailscale monitor; do
  [ -d "/usr/share/omarchy/shell/plugins/panels/$p" ] || echo "warning: stock panel '$p' moved"
done

[ "$fail" -eq 0 ] && echo "upstream references ok"
exit "$fail"
