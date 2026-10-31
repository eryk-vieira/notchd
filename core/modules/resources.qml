import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."
import "../Resources.js" as Resources

// System resources: CPU, memory and the disk holding `diskPath` (/ by
// default). Expanded: a bar each, with how much is used. Closed: all three
// percentages, or, with the `compact` setting at "short", nothing until one
// runs short. One runs short at 90 % or more (the CPU for about 10 s in a
// row, so a burst doesn't count): it turns red, the module peeks once, and
// it stays red until it drops back.
//
// Reads /proc/stat and /proc/meminfo every 2 s and runs `df` every minute.
// Linux only. The rules live in core/Resources.js.
NotchModule {
  id: res
  // Below media and activities: it only takes the closed notch when nothing
  // else wants it. What runs short still peeks.
  priority: 20
  active: true

  // The filesystem shown as Disk: the one holding this path.
  property string diskPath: "/"
  readonly property bool alwaysCompact: res.setting("compact") !== "short"

  // Read the system. Off, the values stay as set from outside (the
  // offscreen renders set them to demo values).
  property bool sampling: true

  // Latest values: a fraction for the CPU, { used, total, fraction } for the
  // others; null until read.
  property var cpu: null
  property int cores: 0
  property var memory: null
  property var disk: null

  // When each one counts as short; see Resources.nextPressure.
  readonly property var rules: ({
    cpu: { warn: 0.9, hold: 5, clear: 0.1 },
    memory: { warn: 0.9, hold: 1, clear: 0.05 },
    disk: { warn: 0.9, hold: 1, clear: 0.02 }
  })
  property var pressure: ({})
  // The one that last ran short, for the peek.
  property string peekId: ""

  readonly property var rows: [
    { id: "cpu", icon: 0xF0EE0, label: "CPU", fraction: res.cpu,  // nf-md-cpu_64_bit
      detail: res.cores > 0 ? res.cores + (res.cores === 1 ? " core" : " cores") : "" },
    { id: "memory", icon: 0xF035B, label: "Memory", fraction: res.memory ? res.memory.fraction : null,  // nf-md-memory
      detail: res.memory ? Resources.formatUsage(res.memory.used, res.memory.total) : "" },
    { id: "disk", icon: 0xF02CA, label: "Disk", fraction: res.disk ? res.disk.fraction : null,  // nf-md-harddisk
      detail: res.disk ? Resources.formatUsage(res.disk.used, res.disk.total) + " · " + res.diskPath : "" }
  ]
  readonly property var shortRows: res.rows.filter(function(r) { return res.isShort(r.id) })
  // What the closed notch shows.
  readonly property var compactRows: res.alwaysCompact ? res.rows : res.shortRows

  function isShort(id) { return !!res.pressure[id] && res.pressure[id].hot }
  function rowById(id) {
    for (var i = 0; i < res.rows.length; i++) if (res.rows[i].id === id) return res.rows[i]
    return null
  }
  function percent(fraction) {
    return fraction === null || fraction === undefined ? "–" : Math.round(fraction * 100) + "%"
  }

  // A new value for `id`: updates its pressure, and peeks when it turns short.
  function record(id, value) {
    var prev = res.pressure[id]
    var next = Resources.nextPressure(prev, value, res.rules[id])
    var all = Object.assign({}, res.pressure)
    all[id] = next
    res.pressure = all
    if (next.hot && !(prev && prev.hot)) {
      res.peekId = id
      res.requestPeek(4000)
    }
  }

  property var lastCpuTimes: null
  function readStat(text) {
    var times = Resources.cpuTimes(text)
    var usage = Resources.cpuUsage(res.lastCpuTimes, times)
    if (times) res.lastCpuTimes = times
    res.cores = Resources.cpuCount(text)
    if (usage !== null) { res.cpu = usage; res.record("cpu", usage) }
  }
  function readMeminfo(text) {
    var m = Resources.memory(text)
    if (m) { res.memory = m; res.record("memory", m.fraction) }
  }
  function readDf(text) {
    var d = Resources.disk(text)
    if (d) { res.disk = d; res.record("disk", d.fraction) }
  }

  FileView {
    id: statFile
    path: res.sampling ? "/proc/stat" : ""
    printErrors: false
    onLoaded: res.readStat(text())
  }
  FileView {
    id: meminfoFile
    path: res.sampling ? "/proc/meminfo" : ""
    printErrors: false
    onLoaded: res.readMeminfo(text())
  }
  Timer {
    interval: 2000
    repeat: true
    running: res.sampling
    onTriggered: { statFile.reload(); meminfoFile.reload() }
  }

  Process {
    id: df
    command: ["df", "-P", "-B1", res.diskPath]
    stdout: StdioCollector { onStreamFinished: res.readDf(text) }
  }
  Timer {
    interval: 60000
    repeat: true
    triggeredOnStart: true
    running: res.sampling
    onTriggered: df.running = true
  }

  // ----------------------------------------------------------------- views
  // None while nothing is to show, so the notch rests.
  compact: res.compactRows.length > 0 ? compactRow : null
  verticalCompact: res.compactRows.length > 0 ? compactColumn : null

  Component {
    id: compactRow
    Row {
      spacing: Theme.space(12)
      Repeater {
        model: res.compactRows
        delegate: Row {
          required property var modelData
          spacing: Theme.space(6)
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String.fromCodePoint(modelData.icon)
            color: res.isShort(modelData.id) ? Theme.danger : Theme.accent
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
          Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: res.percent(modelData.fraction)
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.bodySmall
          }
        }
      }
    }
  }

  // Side edge: each one's icon over its number.
  Component {
    id: compactColumn
    Column {
      spacing: Theme.space(8)
      Repeater {
        model: res.compactRows
        delegate: Column {
          required property var modelData
          spacing: Theme.space(2)
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: String.fromCodePoint(modelData.icon)
            color: res.isShort(modelData.id) ? Theme.danger : Theme.accent
            font.family: Theme.font.family
            font.pixelSize: Theme.font.body
          }
          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            textFormat: Text.PlainText
            text: modelData.fraction === null ? "–" : String(Math.round(modelData.fraction * 100))
            color: Theme.foreground
            font.family: Theme.font.family
            font.pixelSize: Theme.font.caption
          }
        }
      }
    }
  }

  peek: Component {
    ResourceRow {
      row: res.rowById(res.peekId)
      implicitWidth: Theme.space(300)
    }
  }

  expanded: Component {
    Column {
      spacing: Theme.space(12)
      Repeater {
        model: res.rows
        delegate: ResourceRow {
          required property var modelData
          row: modelData
          width: parent.width
        }
      }
    }
  }

  // Icon, name and detail, the percentage, and a bar; red while short.
  component ResourceRow: Item {
    id: item
    property var row: null
    readonly property bool isShort: !!item.row && res.isShort(item.row.id)
    readonly property real fraction: item.row && item.row.fraction !== null ? item.row.fraction : 0
    implicitHeight: layout.implicitHeight

    ColumnLayout {
      id: layout
      anchors.left: parent.left
      anchors.right: parent.right
      spacing: Theme.space(5)

      RowLayout {
        Layout.fillWidth: true
        spacing: Theme.space(10)
        Text {
          Layout.preferredWidth: Theme.space(18)
          textFormat: Text.PlainText
          text: item.row ? String.fromCodePoint(item.row.icon) : ""
          color: item.isShort ? Theme.danger : Theme.accent
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Text {
          textFormat: Text.PlainText
          text: item.row ? item.row.label : ""
          color: Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.body
        }
        Text {
          Layout.fillWidth: true
          textFormat: Text.PlainText
          text: item.row ? item.row.detail : ""
          elide: Text.ElideRight
          color: Theme.muted
          font.family: Theme.font.family
          font.pixelSize: Theme.font.caption
        }
        Text {
          textFormat: Text.PlainText
          text: item.row ? res.percent(item.row.fraction) : ""
          color: item.isShort ? Theme.danger : Theme.foreground
          font.family: Theme.font.family
          font.pixelSize: Theme.font.bodySmall
        }
      }

      Item {
        Layout.fillWidth: true
        implicitHeight: Theme.space(4)
        Rectangle { anchors.fill: parent; radius: height / 2; color: Theme.line }
        Rectangle {
          width: parent.width * item.fraction
          height: parent.height
          radius: height / 2
          color: item.isShort ? Theme.danger : Theme.accent
          Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutCubic } }
        }
      }
    }
  }
}
