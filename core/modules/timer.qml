import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."
import "../Countdown.js" as Countdown

// A countdown timer and a pomodoro. Started from the expanded notch (5, 15
// and 25 minutes, or a pomodoro) or over IPC:
//
//   <notch-ipc> timer 25m           <notch-ipc> timer "3m Tea"
//   <notch-ipc> timer pomodoro      <notch-ipc> timer toggle    (pause / resume)
//   <notch-ipc> timer +5m           <notch-ipc> timer skip      <notch-ipc> timer stop
//
// Closed, it shows the time left while one runs. When the time is up it
// peeks, even over the open notch, and sends a desktop notification
// (notify-send, as any app would). A pomodoro goes focus, short break,
// focus... and a long break after the last round, then stops. The rules
// live in core/Countdown.js.
NotchModule {
  id: t
  // Above media: a running timer is what you started on purpose.
  priority: 60
  // Its end must show even while the notch is open.
  urgentPeek: true
  // Idle, the expanded notch offers the quick starts, and the closed notch
  // shows the icon (the notch's idleIcons).
  active: true
  icon: String.fromCodePoint(0xF051B)  // nf-md-timer_outline

  readonly property var pomodoro: ({
    focus: t.setting("focus"), shortBreak: t.setting("shortBreak"), longBreak: t.setting("longBreak"),
    rounds: t.setting("rounds"), autoAdvance: t.setting("autoAdvance")
  })

  property var countdown: Countdown.IDLE
  property double now: Date.now()

  readonly property string status: t.countdown.status
  readonly property bool counting: t.status === "running" || t.status === "paused"
  readonly property real remaining: Countdown.remaining(t.countdown, t.now)
  readonly property real progress: Countdown.progress(t.countdown, t.now)
  readonly property string clock: Countdown.format(t.remaining)
  readonly property string heading: Countdown.title(t.countdown)
  readonly property int stateGlyph: t.status === "done" ? 0xF009E                     // nf-md-bell_ring
    : t.countdown.kind === "pomodoro" ? (t.countdown.phase === "focus" ? 0xF09D1 : 0xF0176)  // nf-md-brain / nf-md-coffee
    : 0xF051B                                                                    // nf-md-timer_outline
  // What the closed notch says once the time is up.
  readonly property string doneText: t.countdown.next ? "Next: " + Countdown.PHASE_LABELS[t.countdown.next.phase]
    : t.countdown.kind === "pomodoro" ? "Pomodoro done" : "Time's up"

  // An IPC `timer` argument; "ok" or what was wrong.
  function command(text) {
    var cmd = Countdown.parseCommand(text)
    if (cmd.error) return cmd.error
    if (cmd.action !== "start" && cmd.action !== "pomodoro" && cmd.action !== "stop" && t.status === "idle")
      return "no timer running"
    t.run(cmd)
    // A confirmation, unless the notch is open and already shows it.
    if ((cmd.action === "start" || cmd.action === "pomodoro") && !(t.notch && t.notch.expanded)) t.requestPeek(2500)
    return "ok"
  }

  function run(cmd) {
    t.now = Date.now()
    t.countdown = Countdown.apply(t.countdown, cmd, t.now, t.pomodoro)
  }

  function check() {
    t.now = Date.now()
    var r = Countdown.tick(t.countdown, t.now, t.pomodoro)
    if (!r.finished) return
    var ended = t.countdown
    t.countdown = r.state
    t.requestPeek(8000)
    if (t.setting("notify")) t.notify(ended)
  }

  function notify(ended) {
    var body = t.status === "running" ? Countdown.title(t.countdown) + " · " + Countdown.format(t.countdown.duration)
      : ended.kind === "pomodoro" ? t.doneText : (ended.label || Countdown.format(ended.duration) + " timer")
    var head = ended.kind === "pomodoro" ? ended.label + " is over" : "Time's up"
    notifier.command = ["notify-send", "-a", "notchd", "-i", "alarm-symbolic", head, body]
    notifier.running = true
  }
  Process { id: notifier }

  // Wakes as the shown second turns (Countdown.untilChange), about once a
  // second: a fixed 250 ms redrew the notch four times for each change.
  // `check` moves `now`, which sets the next interval.
  Timer {
    interval: Countdown.untilChange(t.countdown, t.now)
    repeat: true
    running: t.status === "running"
    onTriggered: t.check()
  }

  // A done timer goes away after a minute; a pomodoro waiting for its next
  // phase stays until you start it or stop it.
  Timer {
    interval: 60000
    running: t.status === "done" && !t.countdown.next
    onTriggered: t.countdown = Countdown.IDLE
  }

  // ----------------------------------------------------------------- views
  compact: t.status !== "idle" ? compactRow : null
  verticalCompact: t.status !== "idle" ? compactColumn : null

  Component {
    id: compactRow
    Row {
      spacing: Theme.space(8)
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: String.fromCodePoint(t.stateGlyph)
        color: t.status === "paused" ? Theme.muted : Theme.accent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: t.status === "done" ? t.doneText : t.clock
        color: t.status === "paused" ? Theme.muted : Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
        font.features: { "tnum": 1 }
      }
    }
  }

  // Side edge: the icon over the minutes left (seconds in the last one).
  Component {
    id: compactColumn
    Column {
      spacing: Theme.space(2)
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: String.fromCodePoint(t.stateGlyph)
        color: t.status === "paused" ? Theme.muted : Theme.accent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: t.status !== "done"
        textFormat: Text.PlainText
        text: t.remaining >= 60000 ? String(Math.ceil(t.remaining / 60000)) : Math.ceil(t.remaining / 1000) + "s"
        color: t.status === "paused" ? Theme.muted : Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.caption
      }
    }
  }

  // As wide as it needs, up to 300 px; a long label elides.
  peek: Component {
    Item {
      implicitWidth: Math.min(Theme.space(300), peekRow.implicitWidth)
      implicitHeight: peekRow.implicitHeight
      RowLayout {
        id: peekRow
        anchors.fill: parent
        spacing: Theme.space(12)
        Text {
          textFormat: Text.PlainText
          text: String.fromCodePoint(t.stateGlyph)
          color: Theme.accent
          font.family: Theme.font.family
          font.pixelSize: Theme.font.heading
        }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: t.status === "done" ? t.doneText : t.heading
            elide: Text.ElideRight
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: t.status === "done" ? (t.countdown.label || Countdown.format(t.countdown.duration) + " timer") : t.clock + " left"
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
      }
    }
  }

  expanded: Component {
    ColumnLayout {
      spacing: Theme.space(10)

      // Idle: the quick starts.
      ColumnLayout {
        visible: t.status === "idle"
        Layout.fillWidth: true
        spacing: Theme.space(8)
        RowLayout {
          spacing: Theme.space(10)
          Glyph { glyph: 0xF051B; color: Theme.accent }
          Text {
            textFormat: Text.PlainText
            text: "Timer"
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
        }
        RowLayout {
          Layout.fillWidth: true
          spacing: Theme.space(6)
          Repeater {
            model: [5, 15, 25]
            delegate: Chip {
              required property int modelData
              Layout.fillWidth: true
              text: modelData + " min"
              onActivated: t.run({ action: "start", ms: modelData * 60000, label: "" })
            }
          }
          Chip {
            Layout.fillWidth: true
            glyph: 0xF09D1
            text: "Pomodoro"
            onActivated: t.run({ action: "pomodoro" })
          }
        }
      }

      // Running, paused or done: the time and the controls.
      RowLayout {
        visible: t.status !== "idle"
        Layout.fillWidth: true
        spacing: Theme.space(12)
        Glyph { glyph: t.stateGlyph; color: t.status === "paused" ? Theme.muted : Theme.accent; size: Theme.font.heading }
        ColumnLayout {
          Layout.fillWidth: true
          spacing: 0
          Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: t.heading + (t.status === "paused" ? " · paused" : "")
            elide: Text.ElideRight
            color: Theme.muted
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
          Text {
            textFormat: Text.PlainText
            text: t.status === "done" ? t.doneText : t.clock
            color: t.status === "paused" ? Theme.muted : Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: t.status === "done" ? Theme.font.heading : Theme.font.display
            font.features: { "tnum": 1 }
          }
        }
        // Running or paused: pause/resume, then +1 min (timer) or skip
        // (pomodoro), then stop. Done: again or the next phase, then dismiss.
        IconButton {
          visible: t.counting
          glyph: t.status === "running" ? 0xF03E4 : 0xF040A  // nf-md-pause / nf-md-play
          big: true
          onActivated: t.run({ action: "toggle" })
        }
        IconButton {
          visible: t.counting && t.countdown.kind !== "pomodoro"
          glyph: 0xF0415  // nf-md-plus
          onActivated: t.run({ action: "add", ms: 60000 })
        }
        IconButton {
          visible: t.counting && t.countdown.kind === "pomodoro"
          glyph: 0xF04AD  // nf-md-skip_next
          onActivated: t.run({ action: "skip" })
        }
        IconButton {
          visible: t.status === "done" && (!!t.countdown.next || t.countdown.kind !== "pomodoro")
          glyph: t.countdown.next ? 0xF040A : 0xF0709  // nf-md-play / nf-md-restart
          big: true
          onActivated: t.countdown.next ? t.run({ action: "toggle" })
            : t.run({ action: "start", ms: t.countdown.duration, label: t.countdown.label })
        }
        IconButton {
          glyph: t.status === "done" ? 0xF0156 : 0xF04DB  // nf-md-close / nf-md-stop
          onActivated: t.run({ action: "stop" })
        }
      }

      Item {
        visible: t.counting
        Layout.fillWidth: true
        implicitHeight: Theme.space(4)
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.line }
        Rectangle {
          width: parent.width * t.progress
          height: parent.height
          radius: height / 2
          color: t.status === "paused" ? Theme.muted : Theme.accent
        }
      }
    }
  }

  // ------------------------------------------------------------ components
  component Glyph: Text {
    property int glyph: 0
    property int size: Theme.font.body
    textFormat: Text.PlainText
    text: glyph ? String.fromCodePoint(glyph) : ""
    font.family: Theme.font.family
    font.pixelSize: size
  }

  component IconButton: Item {
    id: btn
    property int glyph: 0
    property bool big: false
    signal activated()
    implicitWidth: Theme.space(big ? 36 : 28)
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
      font.pixelSize: btn.big ? Theme.font.heading * 1.25 : Theme.font.heading
    }
    MouseArea {
      id: btnMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: btn.activated()
    }
  }

  component Chip: Rectangle {
    id: chip
    property string text: ""
    property int glyph: 0
    signal activated()
    implicitHeight: Theme.space(32)
    implicitWidth: chipRow.implicitWidth + Theme.space(20)
    radius: Theme.radiusSmall
    color: chipMouse.containsMouse ? Theme.hover : "transparent"
    border.width: 1
    border.color: Theme.line
    Row {
      id: chipRow
      anchors.centerIn: parent
      spacing: Theme.space(6)
      Text {
        visible: chip.glyph !== 0
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.glyph ? String.fromCodePoint(chip.glyph) : ""
        color: Theme.accent
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
      Text {
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        text: chip.text
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
    }
    MouseArea {
      id: chipMouse
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.activated()
    }
  }
}
