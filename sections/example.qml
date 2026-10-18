import QtQuick

// A section — copy this directory entry and this file to add a control.
//
// The contract is five members. Deck reads these and nothing else:
//
//   active  bool    drives the tile's colour
//   label   string  tile title
//   detail  string  tile second line
//   icon    string  glyph
//   toggle()        what a click does
//
// State belongs here, not in the page. The page receives this same object and
// reads it, so the tile and the page cannot disagree.
Item {
  id: s

  property bool active: false

  readonly property string label: "Example"
  readonly property string detail: active ? "on" : "off"
  readonly property string icon: "◇"

  function toggle() {
    active = !active
  }
}
