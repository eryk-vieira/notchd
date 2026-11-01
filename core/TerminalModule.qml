import QtQuick
import QtQuick.Layouts
import Quickshell
import "Agent.js" as Agent
import "Terminal.js" as Terminal
import "Usage.js" as Usage

// Base type for a module that runs a program's own terminal UI in the
// notch: a coding agent (modules/codex.qml, modules/claude.qml). The
// terminal (terminal/TerminalView.qml) comes from the optional
// qmltermwidget package; without it, the open notch says what to install.
// Meant for a notch of its own: closed, it shows the session's title and a
// dot while the program works; open and pinned, the terminal takes the
// keyboard, Escape included; Ctrl+Escape, its button, a shortcut or
// IPC close the notch.
//
// The program starts the first time the notch opens and keeps running while
// it is closed, so the session and whatever it is doing go on (unless
// `idleMinutes` says to stop it); the restart button starts a new one. The
// title and the dot come from the terminal's title, which the program sets
// itself (`parseTitle`, from core/Agent.js). Settings: an agent's JSON file
// says `"agent": { "command": ... }` and gets directory, command,
// idleMinutes, width, height and font (Settings.agentSettings). Over IPC
// (`agent <id> <command>`), command(): "toggle", "new", "ask <text>"
// (Agent.parseCommand).
NotchModule {
  id: m
  priority: 40
  active: true
  expandedWidth: Math.max(320, Number(m.setting("width")) || 760)
  readonly property int terminalHeight: Math.max(120, Number(m.setting("height")) || 420)

  // ------------------------------------------------------------ the module
  // The program's name, in the notch's texts.
  property string appName: ""
  // Run when the `command` setting is empty and has no default (an agent's
  // default is its file's `agent.command`).
  property string defaultCommand: ""
  // Terminal title -> { working, title } (Agent.codexTitle, ...).
  property var parseTitle: null
  // The mark: an image, or a prompt drawn in a tile without one.
  property url logoSource: ""
  // Without a `directory`, start in notchd's own folder (Terminal.OWN_DIR),
  // as an agent does; off, in your home.
  property bool ownDir: true
  // The command is a shell script ("a; b", "cd x && y"), run as is, not
  // one program put in the shell's place (Terminal.shellArgs).
  property bool script: false
  // The IPC function that reaches it, for its usage text: "agent", or
  // "terminal" for one of the config's `terminals`.
  property string ipcName: "agent"

  // ----------------------------------------------------------------- state
  // The widget is installed (Terminal.PROBE). Tests set it.
  property bool available: false
  Component.onCompleted: m.available = m.probe()
  function probe() {
    try {
      Qt.createQmlObject(Terminal.PROBE, m, "terminal-probe").destroy()
      return true
    } catch (e) {
      return false
    }
  }

  // The one terminal (a TerminalView), shown in the last view that opened
  // and parked in the module while none is: its session outlives the views.
  property var term: null
  property string loadError: ""
  readonly property bool exited: !!m.term && m.term.exited
  readonly property string rawTitle: m.term && !m.term.exited ? m.term.title : ""
  // { working, title } from the terminal's title (a demo sets its own).
  property var status: m.parseTitle ? m.parseTitle(m.rawTitle) : { working: false, title: "" }
  readonly property bool working: !!m.status.working
  readonly property string sessionTitle: m.status.title || ""
  // You typed to it: from then on, the end of its work is news.
  property bool typed: false

  property int viewsOpen: 0
  onWorkingChanged: {
    if (m.working) m.attention = false
    // A task ended: its usage moved.
    else if (m.typed) usageSource.refresh()
    if (Agent.donePeek({ wasWorking: !m.working, working: m.working, open: m.viewsOpen > 0, typed: m.typed })) {
      // Done while you weren't looking: news until its view opens.
      m.attention = true
      m.peekReason = "done"
      m.requestPeek(5000)
    }
  }
  // What the peek says: "done" (the agent finished), "usage" (a limit
  // passed the warning, `usageAlert`).
  property string peekReason: "done"

  // ---------------------------------------------------------------- usage
  // The plan's limits (AgentUsage), from the file's `agent.usage`; the
  // settings `usage` (on) and `usageWarn` (%).
  readonly property string usageProvider: {
    var info = m.notch && m.notch.moduleInfo ? m.notch.moduleInfo[m.moduleId] : null
    return info && info.usage ? String(info.usage) : ""
  }
  property alias usage: usageSource
  property var usageAlert: null
  AgentUsage {
    id: usageSource
    provider: m.usageProvider
    live: !!m.notch && m.notch.usageLive
    enabled: m.setting("usage") !== false
    threshold: Number(m.setting("usageWarn")) || 80
    onAlert: function(limit) {
      m.usageAlert = limit
      m.peekReason = "usage"
      m.requestPeek(limit.level >= 100 ? 8000 : 6000)
    }
  }
  readonly property bool showsUsage: usageSource.active && usageSource.limits.length > 0
  onViewsOpenChanged: if (m.viewsOpen > 0) m.attention = false

  // ------------------------------------------------------------- terminal
  function ensureTerm() {
    if (m.term || !m.available) return
    var c = Qt.createComponent(Qt.resolvedUrl("terminal/TerminalView.qml"))
    if (c.status !== Component.Ready) { m.loadError = c.errorString(); return }
    m.loadError = ""
    m.typed = false
    // The command, its folder and the font apply from its next start. No
    // folder of its own: notchd's (Terminal.OWN_DIR), which the shell goes
    // to from the home.
    var dir = String(m.setting("directory") || "").trim()
    m.term = c.createObject(m, {
      program: "/bin/sh",
      programArguments: Terminal.shellArgs(String(m.setting("command") || "").trim() || m.settingDefault("command") || m.defaultCommand,
                                           [], dir === "" && m.ownDir, m.script),
      workingDirectory: Terminal.expandHome(dir, Quickshell.env("HOME")),
      fontFamily: String(m.setting("font") || ""),
      width: Theme.space(m.expandedWidth),
      height: Theme.space(m.terminalHeight),
      visible: false
    })
    m.term.typed.connect(function() { m.typed = true })
    m.term.leave.connect(function() { m.closeNotch() })
  }

  // A new session: the old program stops with its terminal.
  function restart() {
    m.stop()
    m.ensureTerm()
    m.place()
  }
  function stop() {
    m.attention = false
    if (!m.term) return
    m.term.destroy()
    m.term = null
  }

  // Closed and not working for `idleMinutes`, it stops (an agent takes
  // hundreds of MB); the next view starts a new one. 0 keeps it running.
  readonly property real idleMinutes: Number(m.setting("idleMinutes")) || 0
  Timer {
    interval: Math.max(1, m.idleMinutes * 60000)
    running: m.idleMinutes > 0 && !!m.term && !m.working && m.viewsOpen === 0
    onTriggered: m.stop()
  }

  // The views that can show the terminal, the last one opened on top. A
  // view adds its holder when it opens and takes it out when it goes.
  property var holders: []
  function attach(holder) {
    m.holders = m.holders.concat([holder])
    m.ensureTerm()
    m.place()
  }
  function detach(holder) {
    m.holders = m.holders.filter(function(h) { return h !== holder })
    m.place()
  }
  function place() {
    var t = m.term
    if (!t) return
    var holder = m.holders.length > 0 ? m.holders[m.holders.length - 1] : null
    var size = Qt.size(t.width, t.height)
    if (!holder) {
      // Parked at the size it had, so the program doesn't redraw for nothing.
      t.anchors.fill = undefined
      t.parent = m
      t.visible = false
      t.width = size.width
      t.height = size.height
      return
    }
    if (t.parent !== holder) {
      t.parent = holder
      t.anchors.fill = holder
      t.visible = true
      // Moved, the widget draws only the lines that change after; a 1 px
      // nudge redraws it all without changing its grid of cells.
      m.redraw()
      Qt.callLater(m.redraw)
    }
    if (!t.exited) t.forceActiveFocus()
  }
  function redraw() {
    if (!m.term || !m.term.parent) return
    m.term.anchors.rightMargin = 1
    m.term.anchors.rightMargin = 0
  }

  // Once the program is up (its first title), one column narrower and back:
  // the resize makes it draw its whole screen again. Claude Code sends
  // `CSI < u` (kitty keyboard) right after clearing it, which the widget
  // doesn't know and prints as a "u" in the corner.
  property bool settled: false
  onRawTitleChanged: if (m.rawTitle !== "" && !m.settled) { m.settled = true; settleTimer.restart() }
  onTermChanged: m.settled = false
  Timer {
    id: settleTimer
    interval: 600
    onTriggered: {
      if (!m.term || !m.term.visible) return
      m.term.anchors.rightMargin = Math.max(2, m.term.fontMetrics.width + 1)
      unsettleTimer.restart()
    }
  }
  Timer {
    id: unsettleTimer
    interval: 150
    onTriggered: if (m.term) m.term.anchors.rightMargin = 0
  }

  // ------------------------------------------------------------------- IPC
  // "ok", or what was wrong (Agent.parseCommand).
  function command(text) {
    var cmd = Agent.parseCommand(text)
    if (cmd.action === "toggle") return m.toggle()
    if (cmd.action === "new") { m.restart(); return "ok" }
    if (cmd.action === "ask") return m.ask(cmd.text)
    // "avatar ..." is the service's (NotchService.avatarCommand): it works
    // whether the module is loaded or not.
    return "usage: " + m.ipcName + " " + m.moduleId + " toggle | new | \"ask <question>\" | \"avatar <photo>\" | \"avatar remove\""
  }

  // Opens the notch that shows it, on its tab, or closes it while a view
  // shows it: a shortcut that works whatever the notch is called.
  function toggle() {
    if (m.viewsOpen > 0) { m.closeNotch(); return "ok" }
    return m.openNotch() ? "ok" : "no notch shows " + m.moduleId
  }

  // Opens the notch and types `text` into the program, then Enter. A
  // program that is still starting gets it once it has set its first title
  // (it is drawing its UI by then), and a moment later.
  property string pendingAsk: ""
  function ask(text) {
    if (!m.available) return "the terminal needs the qmltermwidget package"
    if (!m.openNotch()) return "no notch shows " + m.moduleId
    if (!text) return "ok"
    m.ensureTerm()
    if (m.exited) m.restart()
    m.pendingAsk = text
    askTimer.restart()
    return "ok"
  }
  Timer {
    id: askTimer
    interval: 500
    onTriggered: {
      if (m.pendingAsk === "" || !m.term || m.exited) return
      if (m.rawTitle === "") { askTimer.restart(); return }
      m.term.write(m.pendingAsk + "\r")
      m.typed = true
      m.pendingAsk = ""
    }
  }

  // ----------------------------------------------------------------- views
  // Closed: [the mark] [the session's title] [a green dot while it works].
  // Nothing in it changes size while working (the dot's place is kept
  // while it is off).
  compact: Component {
    Row {
      spacing: Theme.space(8)
      Logo { anchors.verticalCenter: parent.verticalCenter }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.min(implicitWidth, Theme.space(220))
        textFormat: Text.PlainText
        text: m.sessionTitle || m.appName
        elide: Text.ElideRight
        color: m.sessionTitle ? Theme.foreground : Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
      Working { anchors.verticalCenter: parent.verticalCenter }
    }
  }
  // Down a side edge: the mark, the dot a badge on its corner. A place of
  // its own under the mark, kept while the dot is off, left a gap under
  // every agent in the notch.
  verticalCompact: Component {
    Item {
      implicitWidth: sideLogo.implicitWidth
      implicitHeight: sideLogo.implicitHeight
      Logo { id: sideLogo }
      Rectangle {
        visible: m.working || m.attention
        readonly property real ring: Theme.space(2)
        width: Theme.space(7) + 2 * ring
        height: width
        radius: width / 2
        x: sideLogo.width - width * 0.6
        y: sideLogo.height - height * 0.6
        color: m.working ? Theme.success : Theme.accent
        border.width: ring
        border.color: Theme.background
      }
    }
  }

  peek: Component {
    Row {
      spacing: Theme.space(12)
      Logo { anchors.verticalCenter: parent.verticalCenter; size: Theme.font.heading * 1.5 }
      Column {
        anchors.verticalCenter: parent.verticalCenter
        Text {
          readonly property var alert: m.peekReason === "usage" ? m.usageAlert : null
          textFormat: Text.PlainText
          text: !alert ? m.appName + " is done"
            : alert.level >= 100 ? m.appName + ": " + alert.label + " limit reached"
            : m.appName + ": " + alert.label + " limit at " + Math.round(alert.percent) + " %"
          color: alert && alert.level >= 100 ? Theme.danger : Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Text {
          visible: text !== ""
          width: Math.min(implicitWidth, Theme.space(260))
          textFormat: Text.PlainText
          text: m.peekReason === "usage" && m.usageAlert
            ? (m.usageAlert.resetsAt ? "Resets in " + Usage.resetIn(m.usageAlert.resetsAt, Date.now()) : "")
            : m.sessionTitle
          elide: Text.ElideRight
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
    }
  }

  expanded: Component {
    ColumnLayout {
      id: view
      spacing: Theme.space(10)
      Component.onCompleted: {
        m.viewsOpen++
        if (m.available) m.attach(holder)
      }
      Component.onDestruction: {
        m.viewsOpen--
        m.detach(holder)
      }

      // Header: the mark, the session's title, restart, close.
      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space(10)
        Logo { size: Theme.font.heading }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: m.sessionTitle || m.appName
          elide: Text.ElideRight
          color: m.sessionTitle ? Theme.foreground : Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Working { visible: m.working }
        IconButton {
          visible: m.available && !!m.term && !m.working
          glyph: 0xF0709  // nf-md-restart
          onActivated: m.restart()
        }
        IconButton {
          glyph: 0xF0156  // nf-md-close
          onActivated: m.closeNotch()
        }
      }

      // The plan's limits: a bar each, how much is used and when it resets.
      UsageBars { Layout.fillWidth: true; visible: m.showsUsage }

      // The terminal, in a frame. The terminal itself is m.term, put here
      // while this view is the last one open.
      Rectangle {
        Layout.fillWidth: true
        Layout.preferredHeight: Theme.space(m.terminalHeight)
        visible: m.available
        radius: Theme.radius
        color: Theme.background
        border.width: 1
        border.color: Theme.line
        clip: true

        Item {
          id: holder
          anchors.fill: parent
          anchors.margins: Theme.space(8)
        }

        // A press pins the notch, so its window takes the keyboard; the
        // press goes on to the terminal.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.IBeamCursor
          onPressed: function(mouse) {
            m.requestKeyboard()
            if (m.term && !m.term.exited) m.term.forceActiveFocus()
            mouse.accepted = false
          }
        }

        // The program is gone (quit, or never started): what it printed
        // stays, with a way to start it again.
        Rectangle {
          visible: m.exited
          anchors.left: parent.left
          anchors.right: parent.right
          anchors.bottom: parent.bottom
          anchors.margins: 1
          height: Theme.space(36)
          radius: Theme.radius
          color: Theme.surface
          focus: m.exited
          onVisibleChanged: if (visible) forceActiveFocus()
          Keys.onReturnPressed: m.restart()
          Keys.onEnterPressed: m.restart()
          Text {
            anchors.centerIn: parent
            textFormat: Text.PlainText
            text: m.appName + " exited. Enter or click to start it again."
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
          MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: { m.requestKeyboard(); m.restart() }
          }
        }
      }

      // Without the widget: what to install.
      Text {
        visible: !m.available || m.loadError !== ""
        Layout.fillWidth: true
        Layout.preferredHeight: Math.max(implicitHeight, Theme.space(80))
        verticalAlignment: Text.AlignVCenter
        textFormat: Text.PlainText
        text: m.loadError !== "" ? m.loadError
          : "The " + m.moduleId + " module runs " + m.appName + " in a terminal, which needs the qmltermwidget "
            + "package (the QML port of qtermwidget). Install it, then restart notchd."
        wrapMode: Text.Wrap
        color: m.loadError !== "" ? Theme.danger : Theme.muted
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
    }
  }

  // ------------------------------------------------------------ components
  // The mark at `size` px: `logoSource`, else a prompt in a rounded tile in
  // the theme's colors. Its size from `size` alone: from its own width, a
  // layout feeding the image's implicit size back doubled it each pass.
  component Logo: Item {
    id: logo
    property real size: Theme.font.body * 1.25
    implicitWidth: Math.round(logo.size)
    implicitHeight: implicitWidth
    Image {
      visible: m.logoSource.toString() !== ""
      anchors.fill: parent
      source: m.logoSource
      sourceSize.width: Math.round(logo.size) * 2
      sourceSize.height: Math.round(logo.size) * 2
      fillMode: Image.PreserveAspectFit
      smooth: true
      // Out of the window-sized texture atlas (docs/modules.md).
      mipmap: true
    }
    Rectangle {
      visible: m.logoSource.toString() === ""
      anchors.fill: parent
      radius: Math.round(logo.size / 4)
      color: Theme.foreground
      Text {
        anchors.centerIn: parent
        textFormat: Text.PlainText
        text: ">_"
        color: Theme.background
        font.family: Theme.font.family
        font.pixelSize: Math.max(6, Math.round(logo.size * 0.55))
        font.bold: true
      }
    }
  }
  // The plan's limits in a row (AgentUsage): "5h ▬▬── 42 % · 2h 10m". A
  // bar past the warning is red; stale limits are faint, with why.
  component UsageBars: Flow {
    id: bars
    spacing: Theme.space(16)
    // The time left, kept fresh.
    property real now: Date.now()
    Timer { interval: 30000; running: bars.visible; repeat: true; onTriggered: bars.now = Date.now() }
    Repeater {
      model: usageSource.limits
      delegate: Row {
        required property var modelData
        readonly property bool hot: modelData.percent >= 100
          || (usageSource.threshold < 100 && modelData.percent >= usageSource.threshold)
        spacing: Theme.space(6)
        opacity: usageSource.stale ? 0.55 : 1
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: modelData.label
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
        Rectangle {
          anchors.verticalCenter: parent.verticalCenter
          width: Theme.space(56)
          height: Theme.space(4)
          radius: height / 2
          color: Theme.line
          Rectangle {
            width: parent.width * Math.min(1, modelData.percent / 100)
            height: parent.height
            radius: parent.radius
            color: hot ? Theme.danger : Theme.accent
          }
        }
        Text {
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          text: Math.round(modelData.percent) + " %"
            + (modelData.resetsAt ? " · " + Usage.resetIn(modelData.resetsAt, bars.now) : "")
          color: hot ? Theme.danger : Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
      }
    }
    Text {
      visible: usageSource.stale && usageSource.problem !== ""
      textFormat: Text.PlainText
      text: usageSource.problem
      color: Theme.faint
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
    }
  }

  // A green dot while it works; its place stays while off.
  // Green while it works; the accent once it is done and you haven't
  // looked (`attention`).
  component Working: Item {
    implicitWidth: Theme.space(7)
    implicitHeight: implicitWidth
    Rectangle {
      anchors.fill: parent
      visible: m.working || m.attention
      radius: width / 2
      color: m.working ? Theme.success : Theme.accent
    }
  }
  component IconButton: Item {
    id: btn
    property int glyph: 0
    signal activated()
    implicitWidth: Theme.space(28)
    implicitHeight: implicitWidth
    Rectangle {
      anchors.fill: parent
      radius: width / 2
      color: btnMouse.containsMouse ? Theme.selected : "transparent"
    }
    Text {
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: String.fromCodePoint(btn.glyph)
      color: Theme.foreground
      font.family: Theme.font.family
      font.pixelSize: Theme.font.heading
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }
}
