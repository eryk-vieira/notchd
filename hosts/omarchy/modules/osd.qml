import QtQuick
import Quickshell.Io
import "../../../core"

// Volume, brightness, mic, keyboard light... Every `omarchy osd` call arrives
// as `omarchy-shell osd show <json>` on the "osd" IPC target, which this module
// registers. The stock omarchy.osd plugin owns that target too, so it has to
// be disabled (`omarchy plugin disable omarchy.osd`) for the notch to get it.
NotchModule {
  id: osd
  title: "OSD"
  priority: 100
  urgentPeek: true

  property string icon: ""
  property string message: ""
  property int value: 0
  property int maxValue: 100
  property bool hasProgress: false
  readonly property real fraction: maxValue > 0 ? value / maxValue : 0

  // Glyphs and payload rules mirror Omarchy's own OSD
  // (/usr/share/omarchy/shell/plugins/osd/OsdModel.js, MIT).
  function iconFor(name, percent) {
    var n = String(name || "").toLowerCase()
    if (n === "volume-muted" || n === "volume-mute" || n === "muted" || n === "mute") return ""
    if (n === "volume-low") return ""
    if (n === "volume-medium") return ""
    if (n === "volume-high" || n === "volume") return ""
    if (n === "microphone-muted" || n === "microphone-off" || n === "mic-muted" || n === "mic-off") return "󰍭"
    if (n === "microphone" || n === "mic") return "󰍬"
    if (n === "keyboard") return "󰌌"
    if (n === "brightness" || n === "display") return "󰍹"
    if (n === "touchpad") return "󰟸"
    if (n === "touch" || n === "touchscreen") return "󰝁"
    if (n === "reboot" || n === "restart") return "󰜉"
    if (n === "shutdown" || n === "power" || n === "poweroff") return "󰐥"
    if (n === "logout" || n === "sign-out" || n === "leave") return "󰍃"
    if (n.indexOf("media") === 0 || n.indexOf("player") === 0) {
      if (n.endsWith("play")) return "󰐊"
      if (n.endsWith("pause")) return "󰏤"
      if (n.endsWith("next")) return "󰒭"
      if (n.endsWith("previous")) return "󰒮"
      return "󰝚"
    }
    if (n.length > 0) return name
    if (percent <= 0) return ""
    if (percent <= 33) return ""
    if (percent <= 66) return ""
    return ""
  }

  function show(payloadJson) {
    var p = {}
    try { p = JSON.parse(String(payloadJson || "{}")) } catch (e) {}
    var rawMessage = String(p.message || "")
    var rawValue = p.value === undefined || p.value === null ? "" : String(p.value)
    var maxValue = Math.max(1, parseInt(p.max || "100", 10) || 100)
    var parsed = parseInt(rawValue, 10)
    var hasProgress = rawValue !== "" && !isNaN(parsed) && rawMessage === ""
    var value = hasProgress ? Math.max(0, Math.min(maxValue, parsed)) : 0
    var percent = hasProgress ? Math.round(value * 100 / maxValue) : -1
    var duration = parseInt(p.duration || "1200", 10)

    osd.maxValue = maxValue
    osd.value = value
    osd.hasProgress = hasProgress
    osd.message = rawMessage !== "" ? rawMessage : (hasProgress ? String(p.progressText || (percent + "%")) : "")
    osd.icon = iconFor(String(p.icon || ""), percent)
    osd.requestPeek(isNaN(duration) ? 1200 : Math.max(800, duration))
  }

  IpcHandler {
    target: "osd"
    function show(payloadJson: string): string { osd.show(payloadJson); return "ok" }
    function close(): string { osd.dismissPeek(); return "ok" }
    function state(): string { return osd.notch && osd.notch.peeking(osd) ? "open" : "closed" }
    function ping(): string { return "ok" }
  }

  // Side edge: the bar stands up, the value above it and the icon below.
  verticalPeek: Component {
    Column {
      spacing: Theme.space(10)

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: osd.hasProgress
        // Fixed width so it doesn't shift as the number changes.
        width: Theme.space(38)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: osd.message
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }

      Item {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: osd.hasProgress
        width: Theme.space(6)
        height: Theme.space(140)
        Rectangle {
          anchors.fill: parent
          radius: width / 2
          color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.18)
        }
        Rectangle {
          anchors.bottom: parent.bottom
          width: parent.width
          height: parent.height * osd.fraction
          radius: width / 2
          color: Theme.accent
          Behavior on height { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        textFormat: Text.PlainText
        text: osd.icon
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.heading
      }

      // A message without a bar (mic muted, keyboard light...): beneath the
      // icon, as is.
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        visible: !osd.hasProgress && text !== ""
        textFormat: Text.PlainText
        text: osd.message
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.bodySmall
      }
    }
  }

  peek: Component {
    Row {
      spacing: Theme.space(12)

      Text {
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.space(22)
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: osd.icon
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.heading
      }

      Item {
        visible: osd.hasProgress
        anchors.verticalCenter: parent.verticalCenter
        width: Theme.space(160)
        height: Theme.space(6)
        Rectangle {
          anchors.fill: parent
          radius: height / 2
          color: Qt.rgba(Theme.foreground.r, Theme.foreground.g, Theme.foreground.b, 0.18)
        }
        Rectangle {
          width: parent.width * osd.fraction
          height: parent.height
          radius: height / 2
          color: Theme.accent
          Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
        }
      }

      Text {
        anchors.verticalCenter: parent.verticalCenter
        // Fixed width with a bar so it doesn't shift as the number changes.
        width: osd.hasProgress ? Theme.space(38) : implicitWidth
        horizontalAlignment: osd.hasProgress ? Text.AlignRight : Text.AlignLeft
        textFormat: Text.PlainText
        text: osd.message
        color: Theme.foreground
        font.family: Theme.font.family
        font.pixelSize: Theme.font.body
      }
    }
  }
}
