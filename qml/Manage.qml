import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons

// Section management: what is installed, whether it is the latest, update and
// remove, install from a GitHub link, and the catalogs extra sections come from.
// It owns no registry logic; scripts/deck-sections does, and prints one JSON
// object per call.
Column {
  id: mg

  property string pluginDir: ""
  // The host's install flow (scripts/deck-add-section), shown here so a link
  // pasted on this page reports on this page.
  property bool installing: false
  property string installStatus: ""
  property string installError: ""

  signal back()
  signal installRequested(string url)
  signal registryChanged()

  property var sections: []
  property bool checking: false
  property bool checked: false
  property string message: ""
  property bool needsRestart: false
  property string armedId: ""
  property string busyId: ""
  property var sources: []
  property string sourceError: ""
  property bool sourcesBusy: false

  readonly property string helper: pluginDir + "/scripts/deck-sections"

  spacing: Style.space(4)

  function refresh() {
    message = ""
    if (checking) return
    checking = true
    listProc.command = ["bash", helper, "list"]
    listProc.running = true
    sourcesRun(["sources"])
  }

  function check() {
    checkProc.command = ["bash", helper, "check"]
    checkProc.running = true
  }

  function act(args, id) {
    if (busyId !== "") return
    busyId = id
    message = ""
    actProc.command = ["bash", helper].concat(args)
    actProc.running = true
  }

  function sourcesRun(args) {
    if (sourcesProc.running) return
    sourcesBusy = true
    sourcesProc.command = ["bash", helper].concat(args)
    sourcesProc.running = true
  }

  function statusText(s) {
    var v = s.version !== "" ? "v" + s.version : "no version"
    var out
    if (s.state === "latest") out = v + "  ·  latest"
    else if (s.state === "update") out = v + "  →  v" + s.latest
    else if (s.state === "ahead") out = v + "  ·  ahead of GitHub"
    else if (s.state === "unknown") out = v + "  ·  could not check"
    else if (s.state === "local") out = v + "  ·  local"
    else out = v
    if (s.dirty === true) out += "  ·  edited here"
    return out
  }

  Process {
    id: listProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var res = JSON.parse(String(text || "{}"))
          if (res.sections) mg.sections = res.sections
        } catch (e) {}
        mg.check()
      }
    }
  }

  Process {
    id: checkProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        mg.checking = false
        try {
          var res = JSON.parse(String(text || "{}"))
          if (res.sections) {
            mg.sections = res.sections
            mg.checked = true
          }
        } catch (e) {}
      }
    }
  }

  Process {
    id: actProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        mg.busyId = ""
        var raw = String(text || "").trim()
        try {
          var res = JSON.parse(raw)
          if (res.ok === false) {
            mg.message = String(res.error || "that did not work")
          } else {
            if (res.updated) mg.needsRestart = true
            if (res.removed) mg.registryChanged()
            mg.refresh()
          }
        } catch (e) {
          mg.message = raw !== "" ? raw : "that did not work"
        }
      }
    }
  }

  Process {
    id: sourcesProc
    command: []
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        mg.sourcesBusy = false
        try {
          var res = JSON.parse(String(text || "{}"))
          if (res.ok === false) {
            mg.sourceAddPending = false
            mg.sourceError = String(res.error || "that did not work")
          }
          else if (res.sources) {
            mg.sources = res.sources
            mg.sourceError = ""
            if (sourceAddPending) {
              sourceAddPending = false
              sourceField.text = ""
              mg.registryChanged()
            }
          }
        } catch (e) {}
      }
    }
  }

  property bool sourceAddPending: false

  Timer {
    id: disarm
    interval: 3500
    onTriggered: mg.armedId = ""
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool primary: false
    property bool warn: false
    signal picked()

    width: chipText.implicitWidth + Style.space(16)
    height: Style.space(20)
    radius: Style.cornerRadius
    color: chipMouse.containsMouse
      ? Util.alpha(chip.warn ? Color.urgent : Color.accent, Style.hoverFillAlpha)
      : "transparent"
    border.width: 1
    border.color: chip.primary ? Util.alpha(Color.accent, 0.55)
      : chip.warn ? Util.alpha(Color.urgent, 0.6)
      : Util.alpha(Color.foreground, 0.32)

    Text {
      id: chipText
      anchors.centerIn: parent
      text: chip.label
      color: chip.primary ? Color.accent : chip.warn ? Color.urgent : Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.picked()
    }
  }

  component Caps: Text {
    color: Util.alpha(Color.foreground, 0.45)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
    font.letterSpacing: 1.5
  }

  component Entry: Rectangle {
    property alias text: input.text
    property string placeholder: ""
    signal accepted()
    width: parent ? parent.width : 0
    height: Style.space(28)
    radius: Style.cornerRadius
    color: Util.alpha(Color.foreground, 0.05)
    border.width: 1
    border.color: input.activeFocus ? Util.alpha(Color.accent, 0.7) : Util.alpha(Color.foreground, 0.22)

    Text {
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: Text.AlignVCenter
      visible: input.text === ""
      text: parent.placeholder
      color: Util.alpha(Color.foreground, 0.35)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }

    TextInput {
      id: input
      anchors.fill: parent
      anchors.leftMargin: Style.space(8)
      anchors.rightMargin: Style.space(8)
      verticalAlignment: TextInput.AlignVCenter
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
      clip: true
      selectByMouse: true
      onAccepted: parent.accepted()
    }
  }

  // ---- header: Deck > Sections ----
  Item {
    width: parent.width
    height: Style.space(24)

    // The same arrow every other page has; the crumb is only the second way back.
    Rectangle {
      id: backArrow
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      width: Style.space(24)
      height: Style.space(24)
      radius: Style.cornerRadius
      color: arrowMouse.containsMouse ? Util.alpha(Color.foreground, Style.hoverFillAlpha) : "transparent"
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
        id: arrowMouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mg.back()
      }
    }

    Text {
      id: backText
      anchors.left: backArrow.right
      anchors.leftMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
      text: "Deck"
      color: backMouse.containsMouse ? Color.accent : Util.alpha(Color.foreground, 0.6)
      font.family: Style.font.family
      font.pixelSize: Style.font.title

      MouseArea {
        id: backMouse
        anchors.fill: parent
        anchors.margins: -Style.space(4)
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: mg.back()
      }
    }

    Text {
      id: crumb
      anchors.left: backText.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: "›"
      color: Util.alpha(Color.foreground, 0.4)
      font.family: Style.font.family
      font.pixelSize: Style.font.title
    }

    Text {
      anchors.left: crumb.right
      anchors.leftMargin: Style.space(6)
      anchors.verticalCenter: parent.verticalCenter
      text: "Sections"
      color: Color.foreground
      font.family: Style.font.family
      font.pixelSize: Style.font.title
      font.bold: true
    }

    Chip {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      label: mg.checking ? "Checking…" : "Reload"
      onPicked: {
        mg.registryChanged()
        mg.refresh()
      }
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Util.alpha(Color.foreground, 0.1)
  }

  // After an update the running shell still holds the old code.
  Item {
    visible: mg.needsRestart
    width: parent.width
    height: Style.space(26)

    Text {
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      text: "Updated. Restart to use it."
      color: Color.accent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }

    Chip {
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      label: "Restart shell"
      primary: true
      onPicked: Quickshell.execDetached(["omarchy", "restart", "shell"])
    }
  }

  Caps { text: "INSTALLED" }

  Repeater {
    model: mg.sections

    delegate: Item {
      id: row
      required property var modelData
      readonly property bool armed: mg.armedId === modelData.id
      width: mg.width
      height: Style.space(44)

      Column {
        anchors.left: parent.left
        anchors.right: actions.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: String(row.modelData.title)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
          font.bold: true
        }

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: mg.statusText(row.modelData)
          color: row.modelData.state === "update" ? Color.accent
            : row.modelData.state === "unknown" ? Color.urgent
            : Util.alpha(Color.foreground, 0.55)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Row {
        id: actions
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(6)

        Chip {
          visible: row.modelData.state === "update"
          label: mg.busyId === row.modelData.id ? "Updating…" : "Update"
          primary: true
          onPicked: mg.act(["update", row.modelData.pluginId], row.modelData.id)
        }

        Chip {
          label: row.armed ? "Confirm" : "Remove"
          warn: row.armed
          onPicked: {
            if (row.armed) {
              mg.armedId = ""
              mg.act(["remove", row.modelData.id], row.modelData.id)
            } else {
              mg.armedId = row.modelData.id
              disarm.restart()
            }
          }
        }
      }
    }
  }

  Text {
    visible: mg.sections.length === 0 && !mg.checking
    width: parent.width
    text: "No sections installed"
    color: Util.alpha(Color.foreground, 0.4)
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Text {
    visible: mg.message !== ""
    width: parent.width
    wrapMode: Text.Wrap
    text: mg.message
    color: Color.urgent
    font.family: Style.font.family
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Util.alpha(Color.foreground, 0.1)
  }

  // ---- install from a GitHub link ----
  Caps { text: "ADD FROM GITHUB" }

  Entry {
    id: urlField
    placeholder: "https://github.com/user/omarchy-plugin"
    onAccepted: mg.installRequested(text)
  }

  Item {
    width: parent.width
    height: Style.space(22)

    Chip {
      id: installChip
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      label: mg.installing ? "Installing…" : "Install"
      onPicked: if (!mg.installing) mg.installRequested(urlField.text)
    }

    Text {
      anchors.left: installChip.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: mg.installError !== "" ? mg.installError : mg.installStatus
      color: mg.installError !== "" ? Color.urgent : Util.alpha(Color.foreground, 0.55)
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }

  Rectangle {
    width: parent.width
    height: 1
    color: Util.alpha(Color.foreground, 0.1)
  }

  // ---- where extra sections come from ----
  Caps { text: "SOURCES" }

  Repeater {
    model: mg.sources

    delegate: Item {
      id: src
      required property var modelData
      width: mg.width
      height: Style.space(34)

      Column {
        anchors.left: parent.left
        anchors.right: srcRemove.left
        anchors.rightMargin: Style.space(8)
        anchors.verticalCenter: parent.verticalCenter
        spacing: 1

        Text {
          width: parent.width
          elide: Text.ElideRight
          text: String(src.modelData.name)
          color: Color.foreground
          font.family: Style.font.family
          font.pixelSize: Style.font.body
        }

        Text {
          width: parent.width
          elide: Text.ElideMiddle
          text: String(src.modelData.target)
          color: Util.alpha(Color.foreground, 0.45)
          font.family: Style.font.family
          font.pixelSize: Style.font.caption
        }
      }

      Item {
        id: srcRemove
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        width: Style.space(40)
        height: Style.space(20)

        Chip {
          visible: src.modelData.builtin !== true
          anchors.right: parent.right
          label: "×"
          onPicked: mg.sourcesRun(["source-remove", src.modelData.id])
        }
      }
    }
  }

  Entry {
    id: sourceField
    placeholder: "owner/repo or https address of a catalog.json"
    onAccepted: addSource.picked()
  }

  Item {
    width: parent.width
    height: Style.space(22)

    Chip {
      id: addSource
      anchors.left: parent.left
      anchors.verticalCenter: parent.verticalCenter
      label: mg.sourcesBusy ? "Checking…" : "Add source"
      onPicked: {
        if (mg.sourcesBusy) return
        if (sourceField.text.trim() === "") {
          mg.sourceError = "Enter a repo or an address first"
          return
        }
        mg.sourceError = ""
        mg.sourceAddPending = true
        mg.sourcesRun(["source-add", sourceField.text.trim()])
      }
    }

    Text {
      anchors.left: addSource.right
      anchors.leftMargin: Style.space(8)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      elide: Text.ElideRight
      text: mg.sourceError
      color: Color.urgent
      font.family: Style.font.family
      font.pixelSize: Style.font.caption
    }
  }
}
