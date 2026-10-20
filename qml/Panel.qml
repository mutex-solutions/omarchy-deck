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

  // What the registry shipped. `layout` is the user's override on top of it:
  // which entries are on the grid, in what size. The registry stays a
  // read-only catalogue owned by the plugin or the bundle.
  property var registrySections: []
  property var layout: ({})

  readonly property string layoutPath: Quickshell.env("HOME") + "/.config/deck/layout.json"

  // every arrangement a tile may take, in the order the size chip cycles
  readonly property var sizeChoices: [
    { label: "1×1", span: 1, rows: 1 },
    { label: "2×1", span: 2, rows: 1 },
    { label: "4×1", span: 4, rows: 1 },
    { label: "2×2", span: 2, rows: 2 }
  ]

  // Registry order, with the user's shown/span/rows applied. A registry entry
  // marked hidden is only a default: it can be put on the grid from arrange
  // mode, and a hidden entry is still instantiated so its page stays reachable.
  readonly property var allSections: {
    var out = []
    for (var i = 0; i < registrySections.length; i++) {
      var s = registrySections[i]
      var id = String(s.id)
      var o = layout[id] || ({})
      var span = o.span !== undefined ? Number(o.span) : Number(s.span)
      if (span !== 1 && span !== 2 && span !== 4) span = 2
      var rows = o.rows !== undefined ? Number(o.rows) : Number(s.rows)
      rows = rows === 2 ? 2 : 1
      out.push({
        id: id,
        title: String(s.title || id),
        file: s.file,
        page: s.page,
        defaultHidden: s.hidden === true,
        shown: o.shown !== undefined ? (o.shown === true) : (s.hidden !== true),
        span: span,
        rows: rows
      })
    }
    return out
  }

  readonly property var gridSections: allSections.filter(function(s) { return s.shown })
  readonly property var hiddenSections: allSections.filter(function(s) { return !s.shown })

  function sectionEntry(id) {
    for (var i = 0; i < allSections.length; i++)
      if (allSections[i].id === String(id)) return allSections[i]
    return null
  }

  function sizeLabelFor(entry) {
    if (!entry) return ""
    for (var i = 0; i < sizeChoices.length; i++)
      if (sizeChoices[i].span === entry.span && sizeChoices[i].rows === entry.rows)
        return sizeChoices[i].label
    return entry.span + "×" + entry.rows
  }

  function saveLayout() {
    var payload = JSON.stringify({ version: 1, entries: layout })
    Quickshell.execDetached(["bash", "-c",
      "printf '%s' " + Util.shellQuote(payload) + " > " + Util.shellQuote(root.layoutPath)])
  }

  function updateLayout(id, patch) {
    var next = ({})
    for (var k in layout) next[k] = layout[k]
    var cur = ({})
    var existing = layout[String(id)]
    if (existing) for (var p in existing) cur[p] = existing[p]
    for (var q in patch) cur[q] = patch[q]
    next[String(id)] = cur
    layout = next
    saveLayout()
  }

  function setShown(id, shown) {
    updateLayout(id, { shown: shown === true })
  }

  function cycleSize(id) {
    var entry = sectionEntry(id)
    if (!entry) return
    var index = -1
    for (var i = 0; i < sizeChoices.length; i++)
      if (sizeChoices[i].span === entry.span && sizeChoices[i].rows === entry.rows)
        index = i
    var next = sizeChoices[(index + 1) % sizeChoices.length]
    updateLayout(id, { span: next.span, rows: next.rows })
  }
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
  property bool editing: false

  // Handed to every page. close() is the only navigation a page may trigger;
  // notify() is a one-line message on the notice strip.
  readonly property QtObject host: QtObject {
    // Whether the page is actually on screen. A page that runs a capture or a
    // poll should bind to this rather than staying hot behind a closed panel.
    readonly property bool open: root.opened && root.pageOpen
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
      for (var i = 0; i < root.allSections.length; i++)
        if (root.allSections[i].id === String(id)) entry = root.allSections[i]
      if (!entry) { console.warn("deck: no section", id); return }
      root.openPage(entry)
      root.open()
    }
    function back() { root.closePage() }
    function edit() {
      root.editing = true
      root.closePage()
      root.open()
    }
    // Scriptable arrange actions, for a keybind or a reproducible setup.
    function setSize(id: string, span: int, rows: int) {
      root.updateLayout(id, { span: span, rows: rows })
    }
    function setShown(id: string, shown: bool) {
      root.setShown(id, shown)
    }
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
      root.registrySections = parsed.sections || []
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

  // The user's arrangement. Absent means "the registry defaults", which is a
  // valid state and the one a fresh install is in.
  FileView {
    id: layoutFile
    path: root.layoutPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.layout = parsed.entries || ({})
      } catch (e) {
        console.warn("deck: ~/.config/deck/layout.json is not valid JSON:", e)
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
    // Arrange mode shows the size controls and the add list under the grid;
    // give it the extra room rather than clipping the last control.
    contentHeight: panel.fittedContentHeight(content.implicitHeight,
      root.editing ? Style.space(660) : Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.pageOpen) root.closePage()
        else root.close()
      }
      onActivateRequested: root.close()
    }

    // Hidden sections: instantiated so their `state` is registered and their
    // page can be opened through openSection, but never drawn as a tile.
    Item {
      visible: false
      width: 0
      height: 0

      Repeater {
        model: root.hiddenSections

        delegate: Loader {
          id: hiddenLoader
          required property var modelData
          source: root.resolvePath(String(modelData.file))
          onLoaded: root.registerSection(modelData.id, item)
          onStatusChanged: {
            if (status === Loader.Error)
              console.warn("deck: failed to load section", modelData.id, hiddenLoader.errorString)
          }
        }
      }
    }

    // The grid fits without scrolling, but arrange mode adds the size
    // controls and the full list of sections that are not on the grid. Cap the
    // popup and scroll rather than clipping the last control off the screen.
    ScrollView {
      id: contentScroll
      anchors.fill: parent
      clip: true
      ScrollBar.horizontal.policy: ScrollBar.AlwaysOff
      // Hidden, like every other Deck page: a bar overlays content here.
      ScrollBar.vertical.policy: ScrollBar.AlwaysOff

    Column {
      id: content
      width: contentScroll.availableWidth
      spacing: Style.space(10)

      // ---------------- header ----------------
      Item {
        width: parent.width
        height: Style.space(22)
        visible: !root.pageOpen

        Text {
          id: deckTitle
          anchors.left: parent.left
          anchors.verticalCenter: parent.verticalCenter
          text: "DECK"
          color: Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          font.letterSpacing: 1.5
        }

        Text {
          anchors.left: deckTitle.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: root.editing ? "arrange" : ""
          color: Util.alpha(Color.accent, 0.8)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }

        Rectangle {
          id: editChip
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: editText.implicitWidth + Style.space(16)
          height: Style.space(20)
          radius: Style.cornerRadius
          color: editMouse.containsMouse
            ? Util.alpha(Color.accent, Style.hoverFillAlpha)
            : "transparent"
          border.width: 1
          border.color: Util.alpha(root.editing ? Color.accent : Color.foreground, 0.32)

          Text {
            id: editText
            anchors.centerIn: parent
            text: root.editing ? "Done" : "Edit"
            color: root.editing ? Color.accent : Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: editMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.editing = !root.editing
              if (root.editing) root.closePage()
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        visible: !root.pageOpen
        color: Util.alpha(Color.foreground, 0.1)
      }

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
          model: root.gridSections

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
            editing: root.editing
            sizeLabel: root.sizeLabelFor(modelData)
            onRemoveRequested: root.setShown(modelData.id, false)
            onSizeRequested: root.cycleSize(modelData.id)
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
                  console.warn("deck: failed to load section", modelData.id, sectionLoader.errorString)
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

      // ---------------- arrange: add a control ----------------
      Item {
        width: parent.width
        height: Style.space(18)
        visible: !root.pageOpen && root.editing

        Text {
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          text: root.hiddenSections.length > 0
            ? "Tap a size to resize, × to remove. Add a control below."
            : "Tap a size to resize, × to remove."
          color: Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Column {
        id: addList
        width: parent.width
        spacing: Style.space(2)
        visible: !root.pageOpen && root.editing

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "ADD A CONTROL"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.hiddenSections.length)
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: root.hiddenSections

          delegate: Item {
            required property var modelData
            width: addList.width
            height: Style.space(30)

            Text {
              anchors.left: parent.left
              anchors.leftMargin: Style.space(8)
              anchors.right: addChip.left
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              text: modelData.title
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.body
              elide: Text.ElideRight
            }

            Rectangle {
              id: addChip
              anchors.right: parent.right
              anchors.rightMargin: Style.space(8)
              anchors.verticalCenter: parent.verticalCenter
              width: addText.implicitWidth + Style.space(16)
              height: Style.space(20)
              radius: Style.cornerRadius
              color: addMouse.containsMouse
                ? Util.alpha(Color.accent, Style.hoverFillAlpha)
                : "transparent"
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)

              Text {
                id: addText
                anchors.centerIn: parent
                text: "＋ Add"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.caption
              }

              MouseArea {
                id: addMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.setShown(modelData.id, true)
              }
            }
          }
        }

        Text {
          visible: root.hiddenSections.length === 0
          width: parent.width
          height: Style.space(22)
          verticalAlignment: Text.AlignVCenter
          leftPadding: Style.space(8)
          text: "Everything is on the grid"
          color: Util.alpha(Color.foreground, 0.4)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
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
          // No visible scrollbar: it overlays the right edge of the page
          // content (the display page's rate control and switches) and blocks
          // them. The view still scrolls by wheel and touch.
          ScrollBar.vertical.policy: ScrollBar.AlwaysOff

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
                console.warn("deck: failed to load page", root.pageSource, pageLoader.errorString)
            }
          }
        }
      }
    }
    }
  }

  onOpenedChanged: if (!opened) editing = false

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
