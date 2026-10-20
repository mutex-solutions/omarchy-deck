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
  // The user's display order. A section absent from it keeps its registry
  // position; dragging writes this array.
  property var order: []

  // Drag state. The ghost lives in the popup, outside the scroll view, so it
  // is not clipped by the grid while the pointer moves.
  property string draggingId: ""
  property string dropTargetId: ""
  property real dragX: 0
  property real dragY: 0
  property real dragW: 0
  property real dragH: 0

  // The embedded catalog of first-party sections. It is only a list of what
  // can be installed; the registry is what is actually installed.
  property var catalog: []

  // The size page is for one section: chooserId names it.
  property string chooserId: ""
  property bool installing: false
  property string installStatus: ""
  property string installError: ""
  property string _installOut: ""
  property string _installErr: ""

  // Share/import. The file is the deck's order, sizes and each section's git
  // origin, so another user can install what is missing and get the same deck.
  property bool sharing: false
  property string shareStatus: ""
  property string shareError: ""
  property string _shareOut: ""
  property string _shareErr: ""
  readonly property string sharePathDefault: Quickshell.env("HOME") + "/.config/deck/deck-layout.json"

  readonly property string layoutPath: Quickshell.env("HOME") + "/.config/deck/layout.json"

  // every arrangement a tile may take, in the order the size chip cycles
  readonly property var sizeChoices: [
    { label: "1×1", sub: "1u", span: 1, rows: 1 },
    { label: "2×1", sub: "Half", span: 2, rows: 1 },
    { label: "4×1", sub: "Full", span: 4, rows: 1 },
    { label: "2×2", sub: "Square", span: 2, rows: 2 }
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
    var registryIndex = ({})
    for (var r = 0; r < registrySections.length; r++)
      registryIndex[String(registrySections[r].id)] = r

    out.sort(function(a, b) {
      var ia = order.indexOf(a.id)
      var ib = order.indexOf(b.id)
      if (ia === -1) ia = 100000 + (registryIndex[a.id] || 0)
      if (ib === -1) ib = 100000 + (registryIndex[b.id] || 0)
      return ia - ib
    })
    return out
  }

  readonly property var gridSections: allSections.filter(function(s) { return s.shown })
  readonly property var hiddenSections: allSections.filter(function(s) { return !s.shown })

  function findCatalogEntry(sectionId) {
    for (var i = 0; i < catalog.length; i++) {
      var e = catalog[i]
      var sid = String(e.sectionId || String(e.id || "").split(".").pop())
      if (sid === String(sectionId)) return e
    }
    return null
  }

  // One row per section a user can put on the grid: registered sections in
  // registry order, then catalog entries that are not installed yet. A
  // section already on the grid is still here, with its size choices, which
  // is the point: arrange mode is a catalogue, not an "add the missing ones"
  // list.
  readonly property var catalogEntries: {
    var out = []
    var seen = ({})
    for (var i = 0; i < allSections.length; i++) {
      var s = allSections[i]
      var c = findCatalogEntry(s.id)
      var live = sectionMap[String(s.id)]
      out.push({
        id: s.id,
        title: s.title,
        pluginId: c ? String(c.id) : "",
        repo: c ? String(c.repo || "") : "",
        description: c ? String(c.description || "") : "",
        glyph: live && live.icon !== undefined && String(live.icon) !== ""
          ? String(live.icon) : (c && c.icon ? String(c.icon) : "▦"),
        installed: true,
        shown: s.shown,
        span: s.span,
        rows: s.rows,
        custom: !!(live && live.tileComponent) || s.rows === 2
      })
      seen[String(s.id)] = true
    }
    for (var j = 0; j < catalog.length; j++) {
      var e = catalog[j]
      var id = String(e.sectionId || String(e.id || "").split(".").pop())
      if (seen[id]) continue
      out.push({
        id: id,
        title: String(e.title || e.id || id),
        pluginId: String(e.id || ""),
        repo: String(e.repo || ""),
        description: String(e.description || ""),
        glyph: String(e.icon || "▦"),
        installed: false,
        shown: false,
        span: 2,
        rows: 1,
        custom: false
      })
    }
    return out
  }

  readonly property var onGridEntries: catalogEntries.filter(function(e) { return e.shown })
  readonly property var availableEntries: catalogEntries.filter(function(e) { return !e.shown })

  function catalogEntryById(id) {
    for (var i = 0; i < catalogEntries.length; i++)
      if (catalogEntries[i].id === String(id)) return catalogEntries[i]
    return null
  }

  // The three sizes the owner named, plus 2x2 only where a tile is a custom
  // component that needs the height (the connectivity cluster).
  function sizeChoicesFor(entry) {
    var out = []
    for (var i = 0; i < sizeChoices.length; i++) {
      var c = sizeChoices[i]
      if (c.rows === 2 && !(entry && (entry.custom || entry.rows === 2))) continue
      out.push(c)
    }
    return out
  }

  function applySize(id, span, rows) {
    updateLayout(id, { shown: true, span: span, rows: rows })
  }

  function moveInOrder(id, targetId) {
    id = String(id)
    targetId = String(targetId)
    if (id === "" || targetId === "" || id === targetId) return
    var ids = order.slice()
    // A fresh install may have no order yet; seed it from what is on screen.
    if (ids.length === 0)
      for (var i = 0; i < allSections.length; i++) ids.push(allSections[i].id)
    for (var j = 0; j < allSections.length; j++)
      if (ids.indexOf(allSections[j].id) === -1) ids.push(allSections[j].id)

    ids = ids.filter(function(v) { return v !== id })
    var at = ids.indexOf(targetId)
    if (at === -1) at = ids.length
    ids.splice(at, 0, id)
    order = ids
    saveLayout()
  }

  function beginDrag(id, w, h, cx, cy) {
    draggingId = String(id)
    dropTargetId = ""
    dragW = w
    dragH = h
    dragX = cx
    dragY = cy
  }

  function moveDrag(px, py, target) {
    dragX = px
    dragY = py
    dropTargetId = target
  }

  function moveDragAt(px, py) {
    var target = ""
    var kids = grid.children
    for (var i = 0; i < kids.length; i++) {
      var c = kids[i]
      if (!c || c.modelData === undefined) continue
      if (String(c.modelData.id) === String(draggingId)) continue
      var p = c.mapToItem(gridHost, 0, 0)
      if (px >= p.x && px <= p.x + c.width && py >= p.y && py <= p.y + c.height) {
        target = String(c.modelData.id)
        break
      }
    }
    moveDrag(px, py, target)
  }

  function endDrag() {
    if (draggingId !== "" && dropTargetId !== "" && dropTargetId !== draggingId)
      moveInOrder(draggingId, dropTargetId)
    draggingId = ""
    dropTargetId = ""
  }

  function reloadRegistry() {
    root.userRegistryPresent = true
    userRegistry.reload()
  }

  function installSection(url, pluginId, sectionId, title) {
    url = String(url || "").trim()
    if (installing) return
    if (url === "" && String(pluginId || "") === "") {
      installError = "Paste a GitHub URL first"
      return
    }
    installing = true
    installStatus = ""
    installError = ""
    _installOut = ""
    _installErr = ""
    var cmd = ["bash", root.pluginDir + "/scripts/deck-add-section"]
    if (pluginId) cmd = cmd.concat(["--id", String(pluginId)])
    // The catalog knows the registry key; a pasted URL does not, and the
    // helper then reuses an existing entry or derives one from the manifest.
    if (sectionId) cmd = cmd.concat(["--section-id", String(sectionId)])
    if (title) cmd = cmd.concat(["--title", String(title)])
    if (url !== "") cmd.push(url)
    installProc.command = cmd
    installProc.running = true
  }

  function exportLayout() {
    if (sharing) return
    sharing = true
    shareStatus = ""
    shareError = ""
    _shareOut = ""
    _shareErr = ""
    layoutProc.command = ["bash", root.pluginDir + "/scripts/deck-layout", "export"]
    layoutProc.running = true
  }

  function importLayout(path) {
    path = String(path || "").trim()
    if (sharing) return
    if (path === "") {
      shareError = "Enter the path of a deck file"
      return
    }
    sharing = true
    shareStatus = ""
    shareError = ""
    _shareOut = ""
    _shareErr = ""
    layoutProc.command = ["bash", root.pluginDir + "/scripts/deck-layout", "import", path]
    layoutProc.running = true
  }

  function sizeLabelFor(entry) {
    if (!entry) return ""
    for (var i = 0; i < sizeChoices.length; i++)
      if (sizeChoices[i].span === entry.span && sizeChoices[i].rows === entry.rows)
        return sizeChoices[i].label
    return entry.span + "×" + entry.rows
  }

  function saveLayout() {
    var payload = JSON.stringify({ version: 1, order: order, entries: layout })
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
    // A section that becomes visible for the first time goes at the end; a
    // hidden one keeps its place so re-adding it does not jump the queue.
    if (cur.shown === true && order.indexOf(String(id)) === -1)
      order = order.concat([String(id)])
    saveLayout()
  }

  function setShown(id, shown) {
    updateLayout(id, { shown: shown === true })
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
  // grid: the home surface. catalog: the list of every control. size: the
  // full previews for one control. Editing is a place you go, not a mode the
  // grid wears.
  property string view: "grid"
  // Nothing on the grid is mutable unless this is on: no x, no drag, no +.
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
      root.view = "catalog"
      root.closePage()
      root.open()
    }
    function arrange(on: bool) {
      root.editing = on === true
      root.view = "grid"
      root.closePage()
      root.open()
    }
    function shareExport() { root.exportLayout() }
    function shareImport(path: string) { root.importLayout(String(path)) }
    function shareStatusText(): string {
      return root.shareError !== "" ? root.shareError : root.shareStatus
    }
    // Scriptable arrange actions, for a keybind or a reproducible setup.
    function setSize(id: string, span: int, rows: int) {
      root.updateLayout(id, { span: span, rows: rows })
    }
    function setShown(id: string, shown: bool) {
      root.setShown(id, shown)
    }
    function choose(id: string) {
      root.editing = true
      root.view = "size"
      root.chooserId = String(id)
      root.closePage()
      root.open()
    }
    // Scriptable install and a readable result, for a keybind or a test.
    function install(url: string) {
      root.editing = true
      root.view = "catalog"
      root.installSection(String(url), "", "", "")
    }
    function status(): string {
      if (root.installing) return "installing"
      return root.installError !== "" ? root.installError : root.installStatus
    }
    function home() {
      root.view = "grid"
      root.chooserId = ""
    }
    function move(id: string, target: string) {
      root.moveInOrder(String(id), String(target))
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
        root.order = parsed.order || []
      } catch (e) {
        console.warn("deck: ~/.config/deck/layout.json is not valid JSON:", e)
      }
    }
  }

  // The embedded catalogue: first-party sections and where to get them. It is
  // a suggestion list, not a registry; the registry above says what exists.
  FileView {
    id: catalogFile
    path: root.pluginDir + "/catalog.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: {
      try {
        var parsed = JSON.parse(text() || "{}")
        root.catalog = parsed.sections || []
      } catch (e) {
        console.warn("deck: catalog.json is not valid JSON:", e)
      }
    }
  }

  // ---- section install --------------------------------------------------
  //
  // The helper does the transactional part: clone, read the manifest, require
  // deck/Section.qml, merge one entry into the registry with an atomic rename,
  // and print one JSON object. A failed registration leaves the old registry
  // untouched and the plugin installed but unused, which is recoverable.
  Process {
    id: installProc
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._installOut = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._installErr = String(text || "")
    }

    onExited: function(code) {
      root.installing = false
      var result = null
      try { result = JSON.parse(root._installOut || "{}") } catch (e) {}

      if (code === 0 && result && result.ok === true) {
        root.installStatus = "Added " + String(result.title || result.id || "section")
        root.reloadRegistry()
        if (result.id) root.setShown(String(result.id), true)
        return
      }

      var message = result && result.error ? String(result.error)
        : (root._installErr || root._installOut || "Install failed")
      root.installError = message.trim()
    }
  }

  Process {
    id: layoutProc
    command: []

    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._shareOut = String(text || "")
    }
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root._shareErr = String(text || "")
    }

    onExited: function(code) {
      root.sharing = false
      var result = null
      try { result = JSON.parse(root._shareOut || "{}") } catch (e) {}

      if (code === 0 && result && result.ok === true) {
        if (result.action === "export") {
          root.shareStatus = "Saved " + String(result.count || 0) + " sections to "
            + String(result.path || "")
          return
        }
        var parts = ["Imported " + (result.imported ? result.imported.length : 0) + " sections"]
        if (result.installed && result.installed.length)
          parts.push("installed " + result.installed.join(", "))
        if (result.missing && result.missing.length)
          parts.push("missing " + result.missing.join(", "))
        root.shareStatus = parts.join("; ")
        root.reloadRegistry()
        layoutFile.reload()
        root.view = "grid"
        root.editing = true
        return
      }

      var message = result && result.error ? String(result.error)
        : (root._shareErr || root._shareOut || "Share action failed")
      root.shareError = message.trim()
    }
  }

  // One catalogue row. Every registered section is here, on the grid or not;
  // its size chip opens the full previews. A section that is already placed
  // must not lose its choices just because it is on the deck.
  component CatalogRow: Item {
    id: row

    property var entry: null
    property bool onGrid: false

    signal removeRequested()
    signal installRequested()
    signal sizeRequested()

    width: parent ? parent.width : 0
    height: Style.space(34)

    readonly property bool canSize: !!entry && entry.installed === true

    // The row itself is a door too: a user should not have to find the size
    // chip to see what a control can look like.
    MouseArea {
      anchors.fill: parent
      enabled: row.canSize
      cursorShape: row.canSize ? Qt.PointingHandCursor : Qt.ArrowCursor
      onClicked: row.sizeRequested()
    }

    Column {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, row.width
        - (sizeChip.visible ? sizeChip.width : 0)
        - (removeChip.visible ? removeChip.width : 0)
        - (installChip.visible ? installChip.width : 0)
        - Style.space(30))
      spacing: 0

      Text {
        width: parent.width
        text: row.entry ? row.entry.title : ""
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.body
        font.bold: row.onGrid
        elide: Text.ElideRight
      }

      Text {
        width: parent.width
        text: row.onGrid ? "On the grid" : (row.canSize ? "Installed" : "Not installed")
        color: Util.alpha(Color.foreground, 0.45)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }

    // The size is a door, not a set of thumbnails. Pressing it opens the full
    // previews; the grid stays a grid.
    Rectangle {
      id: sizeChip
      visible: row.canSize
      anchors.right: removeChip.left
      anchors.rightMargin: row.onGrid ? Style.space(6) : Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: sizeText.implicitWidth + Style.space(16)
      height: Style.space(20)
      radius: Style.cornerRadius
      color: sizeMouse.containsMouse
        ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
      border.width: 1
      border.color: Util.alpha(Color.accent, 0.45)

      Text {
        id: sizeText
        anchors.centerIn: parent
        text: row.onGrid
          ? root.sizeLabelFor(row.entry) + "  ▾"
          : "Add  ▾"
        color: Color.accent
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        id: sizeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.sizeRequested()
      }
    }

    Rectangle {
      id: removeChip
      visible: row.onGrid
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: removeText.implicitWidth + Style.space(12)
      height: Style.space(20)
      radius: Style.cornerRadius
      color: removeMouse.containsMouse
        ? Util.alpha(Color.urgent, 0.12) : "transparent"
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.3)

      Text {
        id: removeText
        anchors.centerIn: parent
        text: "×"
        color: Util.alpha(Color.foreground, 0.8)
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        id: removeMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.removeRequested()
      }
    }

    Rectangle {
      id: installChip
      visible: !row.canSize
      anchors.right: parent.right
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      width: installText.implicitWidth + Style.space(14)
      height: Style.space(20)
      radius: Style.cornerRadius
      color: installMouse.containsMouse
        ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
      border.width: 1
      border.color: Util.alpha(Color.foreground, 0.3)

      Text {
        id: installText
        anchors.centerIn: parent
        text: "Install"
        color: Color.foreground
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
      }

      MouseArea {
        id: installMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: row.installRequested()
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
    // A minimum matters because the content is inside a ScrollView: before the
    // popup has a width the grid's implicitHeight is 0, and a zero-height popup
    // is closed by the host before it can lay out.
    contentHeight: Math.max(
      root.view === "grid" ? Style.space(180) : Style.space(360),
      panel.fittedContentHeight(content.implicitHeight,
        root.view === "grid" ? Style.space(560) : Style.space(660)))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        // Esc walks back through the layout pages before it closes the panel.
        if (root.pageOpen) root.closePage()
        else if (root.view === "size") root.view = "catalog"
        else if (root.view === "catalog") root.view = "grid"
        else if (root.editing) root.editing = false
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
        visible: !root.pageOpen && root.view === "grid"

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

        Rectangle {
          id: addChip
          visible: root.editing
          anchors.right: editChip.left
          anchors.rightMargin: Style.space(6)
          anchors.verticalCenter: parent.verticalCenter
          width: Style.space(22)
          height: Style.space(22)
          radius: Style.cornerRadius
          color: addMouse.containsMouse
            ? Util.alpha(Color.accent, Style.hoverFillAlpha)
            : "transparent"
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.45)

          Text {
            anchors.centerIn: parent
            text: "+"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.title
          }

          MouseArea {
            id: addMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.view = "catalog"
              root.closePage()
            }
          }
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
              if (!root.editing) {
                root.view = "grid"
                root.chooserId = ""
              }
            }
          }
        }
      }

      Rectangle {
        width: parent.width
        height: 1
        visible: !root.pageOpen && root.view === "grid"
        color: Util.alpha(Color.foreground, 0.1)
      }

      // ---------------- grid ----------------
      // The host exists so the drag ghost and the grid share a coordinate
      // space: both are in the scrolled content, not in the popup window.
      Item {
        id: gridHost
        width: parent.width
        height: grid.implicitHeight
        visible: !root.pageOpen && root.view === "grid"

      // GridLayout, not Flow: a section may span rows as well as columns (a
      // tile may be 2x2), and Flow cannot place a neighbour beside a two-row
      // tile. Four units across, as in the design mock.
      GridLayout {
        id: grid
        width: parent.width
        visible: !root.pageOpen && root.view === "grid"
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
            draggable: root.editing
            removable: root.editing
            dropTarget: root.editing && root.dropTargetId === modelData.id
              && root.draggingId !== ""
            onRemoveRequested: root.setShown(modelData.id, false)
            onDragStarted: function(x, y) {
              var p = mapToItem(gridHost, x, y)
              root.beginDrag(modelData.id, width, height, p.x, p.y)
            }
            onDragMoved: function(x, y) {
              var p = mapToItem(gridHost, x, y)
              root.moveDragAt(p.x, p.y)
            }
            onDragFinished: root.endDrag()
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

        // The floating copy. The original stays in place at 25% so the grid
        // does not reflow until the drop decides where it lands.
        Item {
          id: dragGhost
          visible: root.draggingId !== ""
          enabled: false
          z: 100
          width: root.dragW
          height: root.dragH
          x: root.dragX - width / 2
          y: root.dragY - height / 2

          Tile {
            anchors.fill: parent
            section: root.sectionMap[root.draggingId]
            draggable: false
            removable: false
            compact: {
              var e = root.catalogEntryById(root.draggingId)
              return !!e && e.span === 1 && e.rows === 1
            }
          }
        }
      }

      // ---------------- page: layout ----------------
      Item {
        width: parent.width
        height: Style.space(24)
        visible: !root.pageOpen && root.editing && root.view === "catalog"

        Rectangle {
          id: catalogBack
          width: Style.space(24)
          height: Style.space(24)
          radius: Style.cornerRadius
          color: catalogBackMouse.containsMouse
            ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
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
            id: catalogBackMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.view = "grid"
              root.chooserId = ""
            }
          }
        }

        Text {
          anchors.left: catalogBack.right
          anchors.leftMargin: Style.space(8)
          anchors.verticalCenter: parent.verticalCenter
          text: "Add a control"
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.title
          font.bold: true
        }

        Rectangle {
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          width: doneText.implicitWidth + Style.space(16)
          height: Style.space(20)
          radius: Style.cornerRadius
          color: doneMouse.containsMouse
            ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
          border.width: 1
          border.color: Util.alpha(Color.accent, 0.45)

          Text {
            id: doneText
            anchors.centerIn: parent
            text: "Done"
            color: Color.accent
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }

          MouseArea {
            id: doneMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: {
              root.view = "grid"
              root.editing = false
            }
          }
        }
      }

      Item {
        width: parent.width
        height: Style.space(18)
        visible: !root.pageOpen && root.editing && root.view === "catalog"

        Text {
          width: parent.width
          anchors.verticalCenter: parent.verticalCenter
          text: "Choose a control, then a size. Choosing a size puts it on the deck."
          color: Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      Column {
        id: onGridList
        width: parent.width
        spacing: Style.space(2)
        visible: !root.pageOpen && root.editing && root.view === "catalog"

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "ON THE GRID"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.onGridEntries.length)
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: root.onGridEntries

          delegate: CatalogRow {
            required property var modelData
            entry: modelData
            onGrid: true
            onSizeRequested: {
              root.chooserId = String(modelData.id)
              root.view = "size"
            }
            onRemoveRequested: root.setShown(modelData.id, false)
          }
        }
      }

      Column {
        id: availableList
        width: parent.width
        spacing: Style.space(2)
        visible: !root.pageOpen && root.editing && root.view === "catalog"

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "AVAILABLE"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }

          Text {
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: String(root.availableEntries.length)
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
          }
        }

        Repeater {
          model: root.availableEntries

          delegate: CatalogRow {
            required property var modelData
            entry: modelData
            onGrid: false
            onSizeRequested: {
              root.chooserId = String(modelData.id)
              root.view = "size"
            }
            onInstallRequested: root.installSection(modelData.repo, modelData.pluginId,
              modelData.id, modelData.title)
          }
        }

        Text {
          visible: root.availableEntries.length === 0
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

      // ---------------- arrange: add from GitHub ----------------
      Column {
        id: githubAdd
        width: parent.width
        spacing: Style.space(4)
        visible: !root.pageOpen && root.editing && root.view === "catalog"

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "ADD FROM GITHUB"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }
        }

        TextField {
          id: repoField
          width: parent.width
          height: Style.space(28)
          placeholderText: "https://github.com/user/omarchy-plugin"
          placeholderTextColor: Util.alpha(Color.foreground, 0.35)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          selectByMouse: true
          background: Rectangle {
            color: Util.alpha(Color.foreground, 0.05)
            border.width: 1
            border.color: Util.alpha(Color.foreground, 0.22)
            radius: Style.cornerRadius
          }
          onAccepted: root.installSection(text, "", "", "")
        }

        Item {
          width: parent.width
          height: Style.space(24)

          Rectangle {
            id: installChip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: installText.implicitWidth + Style.space(16)
            height: Style.space(20)
            radius: Style.cornerRadius
            color: installMouse.containsMouse && installMouse.enabled
              ? Util.alpha(Color.accent, Style.hoverFillAlpha)
              : "transparent"
            border.width: 1
            border.color: Util.alpha(Color.foreground, 0.3)
            opacity: installMouse.enabled ? 1.0 : 0.45

            Text {
              id: installText
              anchors.centerIn: parent
              text: root.installing ? "Installing…" : "Install"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: installMouse
              anchors.fill: parent
              enabled: !root.installing && repoField.text.trim() !== ""
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.installSection(repoField.text, "", "", "")
            }
          }

          Text {
            anchors.left: installChip.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.installError !== ""
              ? root.installError
              : (root.installing ? "Installing…" : root.installStatus)
            color: root.installError !== "" ? Color.urgent
              : Util.alpha(Color.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Only GitHub repositories. A plugin runs with your shell's permissions."
          color: Util.alpha(Color.foreground, 0.35)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // ---------------- page: share ----------------
      Column {
        id: shareBlock
        width: parent.width
        spacing: Style.space(4)
        visible: !root.pageOpen && root.editing && root.view === "catalog"

        Item {
          width: parent.width
          height: Style.space(22)

          Text {
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: "SHARE THIS DECK"
            color: Util.alpha(Color.foreground, 0.45)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.5
          }
        }

        Item {
          width: parent.width
          height: Style.space(24)

          Rectangle {
            id: exportChip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: exportText.implicitWidth + Style.space(16)
            height: Style.space(20)
            radius: Style.cornerRadius
            color: exportMouse.containsMouse && !root.sharing
              ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
            border.width: 1
            border.color: Util.alpha(Color.accent, 0.45)
            opacity: root.sharing ? 0.5 : 1.0

            Text {
              id: exportText
              anchors.centerIn: parent
              text: root.sharing ? "Working…" : "Export"
              color: Color.accent
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: exportMouse
              anchors.fill: parent
              enabled: !root.sharing
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.exportLayout()
            }
          }
        }

        TextField {
          id: shareField
          width: parent.width
          height: Style.space(28)
          text: root.sharePathDefault
          placeholderText: "Path to a deck file"
          placeholderTextColor: Util.alpha(Color.foreground, 0.35)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
          selectByMouse: true
          background: Rectangle {
            color: Util.alpha(Color.foreground, 0.05)
            border.width: 1
            border.color: Util.alpha(Color.foreground, 0.22)
            radius: Style.cornerRadius
          }
          onAccepted: root.importLayout(text)
        }

        Item {
          width: parent.width
          height: Style.space(24)

          Rectangle {
            id: importChip
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            width: importText.implicitWidth + Style.space(16)
            height: Style.space(20)
            radius: Style.cornerRadius
            color: importMouse.containsMouse && !root.sharing
              ? Util.alpha(Color.accent, Style.hoverFillAlpha) : "transparent"
            border.width: 1
            border.color: Util.alpha(Color.foreground, 0.3)
            opacity: root.sharing ? 0.5 : 1.0

            Text {
              id: importText
              anchors.centerIn: parent
              text: "Import"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: importMouse
              anchors.fill: parent
              enabled: !root.sharing
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.importLayout(shareField.text)
            }
          }

          Text {
            anchors.left: importChip.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: root.shareError !== "" ? root.shareError : root.shareStatus
            color: root.shareError !== "" ? Color.urgent
              : Util.alpha(Color.foreground, 0.55)
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }
        }

        Text {
          width: parent.width
          wrapMode: Text.Wrap
          text: "Export writes the order, sizes and each section's repository. "
            + "Import installs what is missing and applies the deck."
          color: Util.alpha(Color.foreground, 0.35)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      // ---------------- page: size ----------------
      //
      // Full previews, one per size, rendered with the real Tile and the
      // live section. The unit is the deck's own unit, so a 4x1 preview is
      // exactly what the 4x1 tile will look like, not an outline.
      Column {
        id: sizeView
        width: parent.width
        spacing: Style.space(8)
        visible: !root.pageOpen && root.editing && root.view === "size"

        readonly property var entry: root.catalogEntryById(root.chooserId)

        Item {
          width: parent.width
          height: Style.space(24)

          Rectangle {
            id: sizeBack
            width: Style.space(24)
            height: Style.space(24)
            radius: Style.cornerRadius
            color: sizeBackMouse.containsMouse
              ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
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
              id: sizeBackMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: root.view = "catalog"
            }
          }

          Text {
            anchors.left: sizeBack.right
            anchors.leftMargin: Style.space(8)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: sizeView.entry ? sizeView.entry.title : "Size"
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.title
            font.bold: true
            elide: Text.ElideRight
          }
        }

        Repeater {
          model: root.sizeChoicesFor(sizeView.entry)

          delegate: Column {
            id: sizeOption
            required property var modelData

            readonly property var entry: sizeView.entry
            readonly property var sectionItem: entry ? root.sectionMap[String(entry.id)] : null
            readonly property real gap: Style.space(6)
            readonly property real unit: Math.max(Style.space(30),
              Math.floor((sizeView.width - 3 * gap - Style.space(16)) / 4))
            readonly property real tileW: modelData.rows === 2
              ? 2 * unit + gap
              : modelData.span * unit + (modelData.span - 1) * gap
            readonly property real tileH: modelData.rows === 2 ? 2 * unit + gap : unit
            readonly property bool current: !!entry
              && entry.span === modelData.span && entry.rows === modelData.rows

            width: sizeView.width
            spacing: Style.space(3)

            Text {
              width: parent.width
              text: modelData.sub + "  ·  " + modelData.label
                + (sizeOption.current ? "  ·  current" : "")
              color: sizeOption.current ? Color.accent
                : Util.alpha(Color.foreground, 0.6)
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
              font.bold: sizeOption.current
            }

            Rectangle {
              width: sizeOption.tileW + Style.space(4)
              height: sizeOption.tileH + Style.space(4)
              color: sizeOption.current
                ? Util.alpha(Color.accent, 0.06) : "transparent"
              border.width: sizeOption.current ? 2 : 1
              border.color: sizeOption.current
                ? Util.alpha(Color.accent, 0.85)
                : Util.alpha(Color.foreground, 0.12)
              radius: Style.cornerRadius
              clip: true

              Tile {
                anchors.fill: parent
                anchors.margins: 2
                section: sizeOption.sectionItem
                compact: sizeOption.modelData.span === 1 && sizeOption.modelData.rows === 1
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                  if (!sizeOption.entry) return
                  root.applySize(sizeOption.entry.id, sizeOption.modelData.span,
                    sizeOption.modelData.rows)
                  root.view = "grid"
                  root.chooserId = ""
                  root.editing = true
                }
              }
            }
          }
        }

        Item {
          width: parent.width
          height: Style.space(24)

          Rectangle {
            visible: !!sizeView.entry && sizeView.entry.shown
            anchors.left: parent.left
            width: sizeRemoveText.implicitWidth + Style.space(16)
            height: Style.space(20)
            radius: Style.cornerRadius
            color: sizeRemoveMouse.containsMouse
              ? Util.alpha(Color.urgent, 0.12) : "transparent"
            border.width: 1
            border.color: Util.alpha(Color.foreground, 0.3)

            Text {
              id: sizeRemoveText
              anchors.centerIn: parent
              text: "Remove from the deck"
              color: Color.foreground
              font.family: Style.font.family
              font.pixelSize: Style.font.caption
            }

            MouseArea {
              id: sizeRemoveMouse
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                if (sizeView.entry) root.setShown(sizeView.entry.id, false)
                root.view = "catalog"
                root.chooserId = ""
              }
            }
          }
        }
      }

      // ---------------- notice strip ----------------
      Item {
        width: parent.width
        height: Style.space(38)
        visible: !root.pageOpen && root.view === "grid" && root.notice !== null

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

  onOpenedChanged: {
    if (!opened) {
      // Reopen on the deck, never on the page that was last shown.
      closePage()
      view = "grid"
      chooserId = ""
      editing = false
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
