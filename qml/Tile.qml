import QtQuick
import qs.Commons

// One tile. It draws chrome and owns the gesture; the section supplies the
// state. Deck knows nothing about what a section controls.
//
//   click        -> toggled()
//   press >450ms -> heldLong()   (and never toggled)
//
// The hold indicator appears only after 180ms, so a light tap renders nothing.
Item {
  id: tile

  property var section: null

  signal toggled()
  signal heldLong()

  readonly property bool active: section ? section.active === true : false
  readonly property string label: section && section.label !== undefined ? String(section.label) : ""
  readonly property string detail: section && section.detail !== undefined ? String(section.detail) : ""
  readonly property string icon: section && section.icon !== undefined ? String(section.icon) : ""

  // A 1-unit tile is a square and cannot hold a glyph and a legible label at
  // once, so it renders icon-only and keeps the name in the tooltip.
  property bool compact: false
  // The grid size, so a section can supply a different body for each shape.
  property int span: 2
  property int rowspan: 1
  property bool editing: false

  // Direct manipulation on the home grid: drag to reorder, × to remove. Both
  // are part of the tile, not an editing mode.
  property bool draggable: false
  property bool dragging: false
  property bool removable: false
  property bool dropTarget: false

  signal removeRequested()
  signal dragStarted(real x, real y)
  signal dragMoved(real x, real y)
  signal dragFinished()

  // A section may supply a body for each size: tileCompact, tileHalf,
  // tileFull, tileSquare. tileComponent remains the one-size fallback, and a
  // section that supplies neither gets the default glyph, title and detail.
  readonly property var sizedComponent: {
    if (!section) return null
    if (tile.compact) return section.tileCompact || section.tileComponent || null
    if (tile.rowspan === 2) return section.tileSquare || section.tileComponent || null
    if (tile.span >= 4) return section.tileFull || section.tileComponent || null
    if (tile.span === 2) return section.tileHalf || section.tileComponent || null
    return section.tileComponent || null
  }

  // A custom body owns its clicks, except while editing: then the host's
  // gesture sits on top so the tile can still be dragged and held.
  readonly property bool custom: !!sizedComponent

  property bool hovered: false
  property bool didLongPress: false

  opacity: tile.dragging ? 0.25 : 1.0

  // Every tile carries the same surface and border, custom body or not. A
  // custom body used to replace the chrome entirely, which left the 4x1
  // Sessions/Audio/Display tiles without a border.
  Rectangle {
    anchors.fill: parent
    radius: Style.cornerRadius
    color: tile.active
      ? Util.alpha(Color.accent, Style.selectedFillAlpha)
      : Util.alpha(Color.foreground, tile.hovered ? Style.hoverFillAlpha : Style.normalFillAlpha)
    border.width: 1
    border.color: tile.active
      ? Util.alpha(Color.accent, 0.55)
      : Util.alpha(Color.foreground, Style.normalBorderAlpha)

    Behavior on color {
      ColorAnimation { duration: 100 }
    }
  }

  // Plain Item + anchors, not a Row: Qt refuses vertical anchors on Row
  // children ("Row will not function") and lays them out anyway, leaving the
  // hit area subtly wrong.
  Loader {
    anchors.fill: parent
    visible: tile.custom
    sourceComponent: tile.sizedComponent
  }

  // Compact size: an icon with the title under it. The title is what makes a
  // 1u tile recognisable without hovering; it elides rather than overflowing.
  Item {
    visible: tile.compact && !tile.custom
    anchors.fill: parent
    anchors.margins: Style.space(4)

    Text {
      anchors.horizontalCenter: parent.horizontalCenter
      anchors.verticalCenter: parent.verticalCenter
      anchors.verticalCenterOffset: -Style.space(6)
      text: tile.icon
      color: tile.active ? Color.accent : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.display
    }

    Text {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      horizontalAlignment: Text.AlignHCenter
      text: tile.label
      color: Util.alpha(Color.foreground, 0.65)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }

  Item {
    visible: !tile.custom && !tile.compact
    anchors.fill: parent
    anchors.margins: Style.space(12)

    Text {
      id: iconText
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: tile.icon
      color: tile.active ? Color.accent : Color.foreground
      font.family: Style.font.family
      // Nerd Font glyphs sit small inside their em box; at heading size they
      // read as punctuation next to the label.
      font.pixelSize: Style.font.display
    }

    Column {
      anchors.left: iconText.right
      anchors.leftMargin: Style.space(11)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      spacing: Style.space(3)

      Text {
        width: parent.width
        text: tile.label
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: true
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: tile.detail
        color: Util.alpha(Color.foreground, tile.active ? 0.75 : 0.55)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
  }


  // Hold indicator. Width is animated, not a spinner: the eye reads "still
  // holding" from progress, and a tap stops before this is ever visible.
  Rectangle {
    id: progress
    anchors.left: parent.left
    anchors.bottom: parent.bottom
    height: 2
    width: 0
    color: Color.accent
    visible: width > 0
  }

  NumberAnimation {
    id: progressAnim
    target: progress
    property: "width"
    to: tile.width
    duration: 270
  }

  Timer {
    id: showProgress
    interval: 180
    onTriggered: {
      progress.width = 0
      progressAnim.start()
    }
  }

  Timer {
    id: holdTimer
    interval: 450
    onTriggered: {
      tile.didLongPress = true
      progressAnim.stop()
      progress.width = 0
      tile.heldLong()
    }
  }

  function endPress() {
    holdTimer.stop()
    showProgress.stop()
    progressAnim.stop()
    progress.width = 0
  }

  // The tile under the pointer while something is being dragged.
  Rectangle {
    visible: tile.dropTarget
    anchors.fill: parent
    anchors.margins: -1
    radius: Style.cornerRadius
    color: "transparent"
    border.width: 2
    border.color: Util.alpha(Color.accent, 0.9)
    z: 5
  }

  // × on a placed tile. Always visible: the user asked to be able to remove a
  // tile directly, and a hidden-on-hover control is one you have to discover.
  // It sits above the gesture MouseArea so its press never toggles the tile.
  Rectangle {
    id: removeButton
    visible: tile.removable
    width: tile.compact ? Style.space(14) : Style.space(16)
    height: width
    radius: width / 2
    anchors.top: parent.top
    anchors.right: parent.right
    anchors.margins: Style.space(2)
    color: removeMouse.containsMouse
      ? Util.alpha(Color.urgent, 0.9)
      : Util.alpha(Color.background, 0.88)
    border.width: 1
    border.color: Util.alpha(Color.foreground, 0.35)
    z: 10

    Text {
      anchors.centerIn: parent
      text: "×"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: removeMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: tile.removeRequested()
    }
  }

  MouseArea {
    anchors.fill: parent
    enabled: !tile.custom || tile.editing
    preventStealing: true
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onEntered: tile.hovered = true
    onExited: tile.hovered = false

    property point pressPoint: Qt.point(0, 0)

    function movedEnough(x, y) {
      var dx = x - pressPoint.x
      var dy = y - pressPoint.y
      return Math.sqrt(dx * dx + dy * dy) >= 10
    }

    onPressed: function(mouse) {
      tile.didLongPress = false
      pressPoint = Qt.point(mouse.x, mouse.y)
      holdTimer.start()
      showProgress.start()
    }

    onPositionChanged: function(mouse) {
      if (!pressed) return
      if (tile.dragging) {
        tile.dragMoved(mouse.x, mouse.y)
        return
      }
      if (!tile.draggable || !movedEnough(mouse.x, mouse.y)) return
      // A drag is not a hold: cancel the hold before it can navigate away.
      tile.endPress()
      tile.dragging = true
      tile.dragStarted(mouse.x, mouse.y)
      tile.dragMoved(mouse.x, mouse.y)
    }

    onReleased: function(mouse) {
      if (tile.dragging) {
        tile.dragMoved(mouse.x, mouse.y)
        tile.dragging = false
        tile.dragFinished()
        return
      }
      tile.endPress()
      if (!tile.didLongPress) tile.toggled()
    }

    onCanceled: function(mouse) {
      if (tile.dragging) {
        tile.dragging = false
        tile.dragFinished()
      } else {
        tile.endPress()
      }
    }
  }
}
