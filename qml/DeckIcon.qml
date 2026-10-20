import QtQuick
import qs.Commons

// The Deck mark: a 2x2 control grid with one tile filled. It reads as a small
// deck of controls at bar size, unlike the generic ▦ glyph it replaces.
Item {
  id: root

  property color color: Color.foreground

  implicitWidth: Style.bar.iconCanvas
  implicitHeight: width

  // The bar's icon canvas is larger than a glyph's painted box. Fill it and
  // the mark looks oversized next to the text glyphs; draw at their optical
  // size instead.
  readonly property real canvas: Math.min(width, height)
  readonly property real size: canvas * 0.66
  readonly property real origin: (canvas - size) / 2
  readonly property real gap: Math.max(1, size * 0.15)
  readonly property real cell: Math.max(1, (size - gap) / 2)
  readonly property real radius: Math.max(1, cell * 0.22)
  readonly property real edge: Math.max(1, size * 0.075)

  // Three outlined tiles and one filled: a control surface with one active.
  component Cell: Rectangle {
    width: root.cell
    height: root.cell
    radius: root.radius
  }

  Cell {
    x: root.origin
    y: root.origin
    color: "transparent"
    border.width: root.edge
    border.color: root.color
  }

  Cell {
    x: root.origin + root.cell + root.gap
    y: root.origin
    color: "transparent"
    border.width: root.edge
    border.color: root.color
  }

  Cell {
    x: root.origin
    y: root.origin + root.cell + root.gap
    color: "transparent"
    border.width: root.edge
    border.color: root.color
  }

  Cell {
    x: root.origin + root.cell + root.gap
    y: root.origin + root.cell + root.gap
    color: root.color
  }
}
