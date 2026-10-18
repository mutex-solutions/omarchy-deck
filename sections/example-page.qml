import QtQuick
import qs.Commons

// A page — what opens when the tile is held.
//
// Deck injects two properties and draws the back button, the title and the
// frame itself. A page that draws its own back button is a contract violation.
//
//   section  the live section instance (state lives there, not here)
//   host     { close(), notify(text) }
Item {
  id: page

  property var section: null
  property var host: null

  implicitHeight: col.implicitHeight

  Column {
    id: col
    width: parent.width
    spacing: Style.space(8)

    Text {
      width: parent.width
      text: "A page renders content. Deck supplies the back button and the title."
      color: Util.alpha(Color.foreground, 0.7)
      font.family: Style.font.family
      font.pixelSize: Style.font.body
      wrapMode: Text.WordWrap
    }

    Text {
      width: parent.width
      text: "section.active = " + (page.section ? page.section.active : "null")
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.body
    }

    Text {
      width: parent.width
      text: "That value lives in the section. This page only reads it, which is "
          + "why the tile and the page can never disagree."
      color: Util.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      wrapMode: Text.WordWrap
    }

    Rectangle {
      width: parent.width
      height: Style.space(28)
      radius: Style.cornerRadius
      color: Util.alpha(Color.accent, Style.selectedFillAlpha)
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.55)

      Text {
        anchors.centerIn: parent
        text: "Toggle from the page"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        onClicked: if (page.section && page.section.toggle) page.section.toggle()
      }
    }
  }
}
