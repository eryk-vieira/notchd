import QtQuick
import QtQuick.Layouts
import ".."
import "Settings.js" as Settings

// `integer` and `number` fields: a slider snapped to `step`, with the value
// beside it. `display: "percent"` shows a 0..1 value as 0 to 100 %.
RowLayout {
  id: control

  property var field: ({})
  property var value
  signal edited(var value)

  readonly property real min: Number(field.min || 0)
  readonly property real max: Number(field.max === undefined ? 100 : field.max)
  readonly property real step: Number(field.step) > 0 ? Number(field.step) : 1
  readonly property real current: Number(control.value) || 0
  readonly property real fraction: control.max > control.min
    ? Math.max(0, Math.min(1, (control.current - control.min) / (control.max - control.min))) : 0

  spacing: Theme.space(12)

  function setFromX(x, width) {
    var f = Math.max(0, Math.min(1, x / Math.max(1, width)))
    var v = Settings.snapToStep(control.min + f * (control.max - control.min), control.min, control.max, control.step)
    if (v !== control.current) control.edited(v)
  }

  Item {
    Layout.preferredWidth: Theme.space(190)
    implicitHeight: Theme.space(28)
    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: Theme.space(4)
      radius: height / 2
      color: Theme.line
      Rectangle {
        width: parent.width * control.fraction
        height: parent.height
        radius: parent.radius
        color: Theme.accent
      }
    }
    Rectangle {
      x: track.width * control.fraction - width / 2
      anchors.verticalCenter: parent.verticalCenter
      width: Theme.space(14)
      height: width
      radius: width / 2
      color: Theme.foreground
      border.width: area.pressed ? Theme.space(3) : 0
      border.color: Theme.alpha(Theme.accent, 0.5)
    }
    MouseArea {
      id: area
      anchors.fill: parent
      cursorShape: Qt.PointingHandCursor
      onPressed: function(mouse) { control.setFromX(mouse.x, width) }
      onPositionChanged: function(mouse) { if (pressed) control.setFromX(mouse.x, width) }
    }
  }

  Label {
    Layout.preferredWidth: Theme.space(64)
    horizontalAlignment: Text.AlignRight
    wrapMode: Text.NoWrap
    text: control.field.display === "percent" ? Math.round(control.current * 100) + " %"
      : control.current + (control.field.unit ? " " + control.field.unit : "")
    font.pixelSize: Theme.font.bodySmall
  }
}
