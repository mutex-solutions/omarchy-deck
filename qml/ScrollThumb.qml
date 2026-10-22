import QtQuick
import qs.Commons

// A thin position mark for a ScrollView whose own bar is hidden.
//
// Deck hides the bar because it overlays the right edge of a page and blocks
// the controls there. Hiding it also hides the fact that the page scrolls at
// all, so content past the fold read as missing. This sits in the card's
// padding, outside the page, and shows only while there is more to see.
//
// Size it as the track: anchor it to the full height of the scrolled area.
Item {
  id: track

  // The ScrollView whose position this reports.
  property var view: null

  // ScrollView's own contentHeight is the size of what it holds; the position
  // lives on the Flickable it builds around it.
  readonly property var flick: view ? view.contentItem : null
  readonly property real total: view ? view.contentHeight : 0
  readonly property real shown: view ? view.availableHeight : 0
  readonly property real offset: flick && flick.contentY !== undefined ? flick.contentY : 0

  visible: total > shown + 1
  width: Style.space(3)

  Rectangle {
    width: parent.width
    radius: width / 2
    color: Util.alpha(Color.foreground, 0.35)
    height: Math.max(Style.space(18), track.height * track.shown / Math.max(1, track.total))
    y: {
      var travel = Math.max(0, track.height - height)
      var range = Math.max(1, track.total - track.shown)
      return Math.max(0, Math.min(travel, track.offset / range * travel))
    }
  }
}
