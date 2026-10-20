import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Ui
import qs.Commons

// Deck: a pluggable control surface.
//
// The panel is a host. It owns the popup, the grid, the page swap and the
// gestures; it knows nothing about Wi-Fi or Bluetooth. Everything it shows
// comes from the section files listed in sections.json, each of which is a QML
// component exposing:
//
//   active, label, detail, icon, stockPanel, toggle()
//
// and optionally a `page`, a component Deck renders in place of the grid,
// under a back button. The page owns its own data and actions.
//
// Adding a control = one file + one line in sections.json. This file does not
// change, which is the property worth protecting: if a new section ever needs
// an edit here, the contract is wrong.
Panel {
  id: root

  moduleName: "mutex-solutions.deck"
  ipcTarget: "mutex-solutions.deck"

  // Resolved from HOME rather than a relative URL: FileView and Loader need a
  // stable base, and a relative one resolves against the shell's cwd.
  readonly property string pluginDir: Quickshell.env("HOME") + "/.config/omarchy/plugins/mutex-solutions.deck"

  property var sections: []
  // id -> loaded section item, so an IPC call or keybind can drive a section
  // without the panel being open.
  property var sectionMap: ({})

  // The first notice any section publishes. A section exposes
  // `notice = { severity, title, detail }` or null; Deck draws the strip, so the
  // grid stays pure controls and severity can be graded honestly.
  readonly property var notice: {
    for (var id in sectionMap) {
      var item = sectionMap[id]
      if (item && item.notice && item.notice.title) return item.notice
    }
    return null
  }

  property string pageSource: ""
  property string pageTitle: ""
  property string pageSectionId: ""
  readonly property bool pageOpen: pageSource !== ""

  // Handed to every page. close() is the only navigation a page may trigger;
  // notify() is a one-line message on the notice strip.
  readonly property QtObject host: QtObject {
    function close() { root.closePage() }
    function notify(text) { console.log("deck:", String(text)) }
  }

  // A section may live in this plugin or in another installed plugin. Absolute
  // paths are how the bundle wires sections from their own repositories without
  // copying files into Deck.
  function resolvePath(path) {
    var value = String(path || "")
    if (value === "") return ""
    return value.charAt(0) === "/" ? "file://" + value : root.pluginDir + "/" + value
  }

  function registerSection(id, item) {
    var next = ({})
    for (var k in sectionMap) next[k] = sectionMap[k]
    next[String(id)] = item
    sectionMap = next
  }

  function toggleSection(id) {
    var item = sectionMap[String(id)]
    if (item && typeof item.toggle === "function") item.toggle()
    else console.warn("deck: no section named", id)
  }

  // Hold: open this section's page inside Deck. If it has no page, fall back to
  // the stock Omarchy panel. Still useful, and better than doing nothing.
  function openPage(entry) {
    if (!entry) return
    if (entry.page) {
      pageTitle = String(entry.title || entry.id || "")
      pageSectionId = String(entry.id || "")
      pageSource = root.resolvePath(String(entry.page))
      return
    }
    var item = sectionMap[String(entry.id)]
    if (item && item.stockPanel) root.openStock(item)
  }

  function closePage() {
    pageSource = ""
    pageTitle = ""
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  // manageIpc false so this panel can own the target: the base handler would
  // otherwise occupy it and leave no room for the extra methods.
  manageIpc: false

  IpcHandler {
    target: "mutex-solutions.deck"
    function open() { root.open() }
    function close() { root.close() }
    function toggle() { root.toggle() }
    // Explicit types: an untyped argument is QVariant, which cannot cross IPC.
    function toggleSection(id: string) { root.toggleSection(id) }
    function openSection(id: string) {
      var entry = null
      for (var i = 0; i < root.sections.length; i++)
        if (String(root.sections[i].id) === String(id)) entry = root.sections[i]
      if (!entry) { console.warn("deck: no section", id); return }
      root.openPage(entry)
      root.open()
    }
    function back() { root.closePage() }
  }

  // ---- section registry -------------------------------------------------
  //
  // Two registries, user first. ~/.config/deck/sections.json lets the bundle
  // point at sections living in their own installed plugins without editing
  // this plugin's git checkout; the bundled file is the fallback.
  property bool userRegistryPresent: false

  function loadSections(raw, source) {
    try {
      var parsed = JSON.parse(raw || "{}")
      root.sections = parsed.sections || []
    } catch (e) {
      // A malformed registry must not take the bar down. Keep what was
      // loaded before and say so where a developer will see it.
      console.warn("deck: " + source + " is not valid JSON:", e)
    }
  }

  FileView {
    id: userRegistry
    path: Quickshell.env("HOME") + "/.config/deck/sections.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      root.userRegistryPresent = true
      root.loadSections(text(), "~/.config/deck/sections.json")
    }
  }

  FileView {
    id: bundledRegistry
    path: root.pluginDir + "/sections.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: if (!root.userRegistryPresent) root.loadSections(text(), "bundled sections.json")
  }

  // ---- bar button -------------------------------------------------------
  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "▦"
    onPressed: function(b) { root.toggle() }
  }

  // ---- popup ------------------------------------------------------------
  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    // fittedContentHeight already adds verticalContentInset (padding * 2), so
    // adding padding here as well leaves a dead band under the content.
    contentHeight: panel.fittedContentHeight(content.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.pageOpen) root.closePage()
        else root.close()
      }
      onActivateRequested: root.close()
    }

    Column {
      id: content
      anchors.top: parent.top
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Style.space(10)

      // ---------------- grid ----------------
      // GridLayout, not Flow: a section may span rows as well as columns (the
      // connectivity cluster is 2x2), and Flow cannot place a neighbour beside
      // a two-row tile. Four units across, as in the design mock.
      GridLayout {
        id: grid
        width: parent.width
        visible: !root.pageOpen
        columns: 4
        columnSpacing: Style.space(9)
        rowSpacing: Style.space(9)
        readonly property real unit: (width - 3 * columnSpacing) / 4

        Repeater {
          model: root.sections

          delegate: Tile {
            required property var modelData

            // span is in grid units: 1 narrow, 2 half (default), 4 full row.
            readonly property int span: {
              var n = Number(modelData.span)
              return (n === 1 || n === 2 || n === 4) ? n : 2
            }
            // rows is 1 by default; 2 makes a 2x2 cluster tile.
            readonly property int rowspan: Number(modelData.rows) === 2 ? 2 : 1

            compact: span === 1 && rowspan === 1
            Layout.columnSpan: span
            Layout.rowSpan: rowspan
            Layout.preferredWidth: Math.floor(span * grid.unit + (span - 1) * grid.columnSpacing)
            Layout.preferredHeight: Math.floor(rowspan * grid.unit + (rowspan - 1) * grid.rowSpacing)
            Layout.fillWidth: false
            Layout.fillHeight: false

            Loader {
              id: sectionLoader
              source: root.resolvePath(modelData.file)
              onLoaded: root.registerSection(modelData.id, item)
              onStatusChanged: {
                if (status === Loader.Error)
                  console.warn("deck: failed to load section", modelData.id, sectionLoader.errorString())
              }
            }

            section: sectionLoader.item

            // A section with no toggle() has nothing to switch, so the tap
            // does what the hold would: it opens the page. Otherwise a tap on
            // a read-only tile would be a dead press.
            onToggled: {
              if (sectionLoader.item && typeof sectionLoader.item.toggle === "function")
                sectionLoader.item.toggle()
              else
                root.openPage(modelData)
            }

            onHeldLong: root.openPage(modelData)
          }
        }
      }

      // ---------------- notice strip ----------------
      Item {
        width: parent.width
        height: Style.space(38)
        visible: !root.pageOpen && root.notice !== null

        readonly property bool urgent: !!root.notice && root.notice.severity === "urgent"

        Rectangle {
          anchors.fill: parent
          color: Util.alpha(parent.urgent ? Color.urgent : Color.foreground, 0.05)
          border.width: 1
          border.color: Util.alpha(Color.foreground, 0.16)
        }

        Rectangle {
          width: 2
          height: parent.height
          color: parent.urgent ? Color.urgent : Util.alpha(Color.foreground, 0.34)
        }

        Text {
          id: noticeGlyph
          anchors.left: parent.left
          anchors.leftMargin: Style.space(9)
          anchors.verticalCenter: parent.verticalCenter
          text: parent.urgent ? "!" : "⚡"
          color: parent.urgent ? Color.urgent : Util.alpha(Color.foreground, 0.7)
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Column {
          anchors.left: noticeGlyph.right
          anchors.leftMargin: Style.space(8)
          anchors.right: parent.right
          anchors.rightMargin: Style.space(9)
          anchors.verticalCenter: parent.verticalCenter
          spacing: 1

          Text {
            width: parent.width
            text: root.notice ? String(root.notice.title) : ""
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.bold: true
            elide: Text.ElideRight
          }

          Text {
            width: parent.width
            visible: !!root.notice && !!root.notice.detail
            text: root.notice ? String(root.notice.detail) : ""
            color: Util.alpha(Color.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }
      }

      // ---------------- page ----------------
      Column {
        width: parent.width
        visible: root.pageOpen
        spacing: Style.space(10)

        // No anchors on Row children: Qt refuses them and lays out anyway.
        Row {
          width: parent.width
          height: Style.space(24)
          spacing: Style.space(8)

          Rectangle {
            width: Style.space(24)
            height: Style.space(24)
            radius: Style.cornerRadius
            color: backMouse.containsMouse
              ? Util.alpha(Color.foreground, Style.hoverFillAlpha)
              : "transparent"
            border.width: 1
            border.color: Util.alpha(Color.foreground, Style.normalBorderAlpha)

            Text {
              anchors.centerIn: parent
              text: "←"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
            }

            MouseArea {
              id: backMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.closePage()
            }
          }

          Text {
            height: parent.height
            verticalAlignment: Text.AlignVCenter
            text: root.pageTitle
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
          }
        }

        // Pages can be long (a network list, a device list). Cap the height and
        // scroll rather than letting the panel grow past the screen.
        ScrollView {
          id: pageScroll
          width: parent.width
          height: Math.min(pageLoader.item ? pageLoader.item.implicitHeight : 0, Style.space(420))
          clip: true
          ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
          ScrollBar.vertical.policy: (pageLoader.item && pageLoader.item.implicitHeight > height)
            ? ScrollBar.AsNeeded : ScrollBar.AlwaysOff

          Loader {
            id: pageLoader
            width: pageScroll.availableWidth
            source: root.pageSource
          // The page is a VIEW of the section, not a second copy of its state:
          // it is handed the live instance. Tile and page cannot disagree.
          onLoaded: {
            if (!item) return
            if ("section" in item) item.section = root.sectionMap[String(root.pageSectionId)]
            if ("host" in item) item.host = root.host
            // Sections from other repositories keep their logic in a `state`
            // object; the page is rendered by both Deck and the standalone
            // widget, so it binds to `state` rather than to Deck's wrapper.
            if ("state" in item) {
              var sec = root.sectionMap[String(root.pageSectionId)]
              item.state = sec && sec.state ? sec.state : sec
            }
          }
            onStatusChanged: {
              if (status === Loader.Error)
                console.warn("deck: failed to load page", root.pageSource, pageLoader.errorString())
            }
          }
        }
      }
    }
  }

  // ---- optional: open a section's stock Omarchy panel ---------------------
  //
  // Only used when a section declares no page. A bar-widget's popup can only be
  // opened through its live bar slot, so this is a summon, not an embed, and
  // only one popout exists at a time.
  function openStock(section) {
    if (!section || !section.stockPanel) return
    root.close()
    Quickshell.execDetached(["omarchy-shell", "shell", "summon", String(section.stockPanel), "{}"])
  }
}
