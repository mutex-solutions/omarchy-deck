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

  // A section may supply its own tile body (the connectivity cluster is four
  // buttons, not one glyph). When it does, the host's default body and its
  // gesture are disabled so the custom controls receive the clicks.
  readonly property bool custom: !!(section && section.tileComponent)

  property bool hovered: false
  property bool didLongPress: false

  // A custom tile draws its own body (the connectivity cluster is four
  // buttons), so the host's surface and border would just be a box around them.
  Rectangle {
    visible: !tile.custom
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
    anchors.margins: Style.space(8)
    visible: tile.custom
    sourceComponent: tile.custom && tile.section ? tile.section.tileComponent : null
  }

  Item {
    visible: !tile.custom
    anchors.fill: parent
    anchors.margins: Style.space(12)

    // compact square: glyph only, centred
    Text {
      visible: tile.compact
      anchors.centerIn: parent
      text: tile.icon
      color: tile.active ? Color.accent : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.display
    }

    Text {
      id: iconText
      visible: !tile.compact
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
      visible: !tile.compact
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

  MouseArea {
    anchors.fill: parent
    enabled: !tile.custom
    hoverEnabled: true
    acceptedButtons: Qt.LeftButton
    cursorShape: Qt.PointingHandCursor

    onEntered: tile.hovered = true
    onExited: tile.hovered = false

    onPressed: {
      tile.didLongPress = false
      holdTimer.start()
      showProgress.start()
    }

    onReleased: {
      tile.endPress()
      if (!tile.didLongPress) tile.toggled()
    }

    onCanceled: tile.endPress()
  }
}
