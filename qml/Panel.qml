import QtQuick
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
      pageSource = root.pluginDir + "/" + String(entry.page)
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
  FileView {
    id: registry
    path: root.pluginDir + "/sections.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.sections = parsed.sections || []
      } catch (e) {
        // A malformed registry must not take the bar down. Keep what was
        // loaded before and say so where a developer will see it.
        console.warn("deck: sections.json is not valid JSON:", e)
      }
    }
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
      // Flow, not Grid: Flow honours a child's width, so a section can claim a
      // full row by asking for span 2. Grid would clip it into a column.
      Flow {
        id: grid
        width: parent.width
        visible: !root.pageOpen
        spacing: Style.space(10)

        Repeater {
          model: root.sections

          delegate: Tile {
            required property var modelData

            // span 2 = a full row; anything else = half
            readonly property int span: modelData.span === 2 ? 2 : 1
            width: span === 2 ? grid.width : (grid.width - grid.spacing) / 2
            height: Style.space(78)

            Loader {
              id: sectionLoader
              source: root.pluginDir + "/" + modelData.file
              onLoaded: root.registerSection(modelData.id, item)
              onStatusChanged: {
                if (status === Loader.Error)
                  console.warn("deck: failed to load section", modelData.id, sectionLoader.errorString())
              }
            }

            section: sectionLoader.item

            onToggled: {
              if (sectionLoader.item && typeof sectionLoader.item.toggle === "function")
                sectionLoader.item.toggle()
            }

            onHeldLong: root.openPage(modelData)
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

        Loader {
          id: pageLoader
          width: parent.width
          source: root.pageSource
          // The page is a VIEW of the section, not a second copy of its state:
          // it is handed the live instance. Tile and page cannot disagree.
          onLoaded: {
            if (!item) return
            if ("section" in item) item.section = root.sectionMap[String(root.pageSectionId)]
            if ("host" in item) item.host = root.host
          }
          onStatusChanged: {
            if (status === Loader.Error)
              console.warn("deck: failed to load page", root.pageSource, pageLoader.errorString())
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
