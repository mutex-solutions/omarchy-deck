#!/usr/bin/env bash
#
# Deck, with the author's sections.
#
# Two installs exist:
#
#   omarchy plugin add https://github.com/mutex-solutions/omarchy-deck --enable
#       Deck alone. Ships one example section.
#
#   ./install-bundle.sh
#       Deck, plus every section below, wired into Deck's panel.
#
# Sections are installed from their own repositories and are NOT placed in the
# bar: Deck hosts them. Pass --bar to also enable each one as a standalone bar
# widget (each section works both ways).
#
# Writes ~/.config/deck/sections.json, which Deck prefers over the registry in
# its own git checkout, so `omarchy plugin update mutex-solutions.deck` stays
# clean.

set -euo pipefail

DECK_URL="https://github.com/mutex-solutions/omarchy-deck.git"
DECK_ID="mutex-solutions.deck"
PLUGINS="$HOME/.config/omarchy/plugins"
USER_REGISTRY="$HOME/.config/deck/sections.json"

WITH_BAR=0
NO_RESTART=0
for arg in "$@"; do
  case "$arg" in
    --bar)        WITH_BAR=1 ;;
    --no-restart) NO_RESTART=1 ;;
    -h|--help)    sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *)            echo "unknown option '$arg'" >&2; exit 1 ;;
  esac
done

say() { printf '  %s\n' "$*"; }
die() { printf 'install-bundle: %s\n' "$*" >&2; exit 1; }

command -v omarchy >/dev/null || die "this is not an Omarchy machine"

# id | repo | title | span | rows
SECTIONS=(
  "mutex-solutions.connectivity|https://github.com/mutex-solutions/omarchy-connectivity.git|Connectivity|2|2"
  "mutex-solutions.audio|https://github.com/mutex-solutions/omarchy-audio.git|Audio|2|1"
  "mutex-solutions.display|https://github.com/mutex-solutions/omarchy-display.git|Display|2"
  "mutex-solutions.nightlight|https://github.com/mutex-solutions/omarchy-nightlight.git|Night light|2"
  "mutex-solutions.lid-awake|https://github.com/mutex-solutions/omarchy-lid-awake.git|Lid Awake|2"
)

installed() { [ -f "$PLUGINS/$1/manifest.json" ]; }
enabled()   { omarchy plugin list 2>/dev/null | grep -q "^$1[[:space:]]*enabled"; }

echo "install-bundle: Deck + sections"

# Deck itself.
if installed "$DECK_ID"; then
  say "deck        -> already installed"
else
  omarchy plugin add "$DECK_URL" >/dev/null || die "could not install Deck"
  say "deck        -> installed"
fi
if enabled "$DECK_ID"; then
  say "deck        -> enabled"
else
  omarchy plugin enable "$DECK_ID" --section right >/dev/null || die "could not enable Deck"
  say "deck        -> enabled"
fi

# Sections.
mkdir -p "$(dirname "$USER_REGISTRY")"
entries=""
for row in "${SECTIONS[@]}"; do
  IFS='|' read -r id url title span rows <<< "$row"

  if installed "$id"; then
    say "$id -> already installed"
  else
    omarchy plugin add "$url" >/dev/null || die "could not install $id"
    say "$id -> installed"
  fi

  if [ "$WITH_BAR" = "1" ] && ! enabled "$id"; then
    omarchy plugin enable "$id" --section right >/dev/null || true
    say "$id -> enabled in the bar"
  fi

  section_file="$PLUGINS/$id/deck/Section.qml"
  page_file="$PLUGINS/$id/deck/Page.qml"
  [ -f "$section_file" ] || die "$id has no deck/Section.qml"

  [ -n "$entries" ] && entries="$entries,"
  entries="$entries
    { \"id\": \"$(basename "$id" | cut -d. -f2)\", \"title\": \"$title\", \"file\": \"$section_file\", \"page\": \"$page_file\", \"span\": $span, \"rows\": ${rows:-1} }"
done

cat > "$USER_REGISTRY" <<EOF
{
  "_comment": "Written by omarchy-deck install-bundle.sh. Section paths point at their own installed plugins. Delete this file to fall back to Deck's bundled registry.",
  "sections": [$entries
  ]
}
EOF

say "registry    -> $USER_REGISTRY"

if [ "$NO_RESTART" = "0" ]; then
  omarchy restart shell >/dev/null 2>&1 || true
  say "shell       -> restarted"
fi

echo "install-bundle: done"
