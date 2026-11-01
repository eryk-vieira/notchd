import QtQuick
import ".."

// `choice` field with `display: "chips"`: a chip per option, wrapping under
// the label, the selected one raised. For a long list of short options (a
// voice), which segments couldn't hold.
Flow {
  id: control

  property var field: ({})
  property var value
  signal edited(var value)

  spacing: Theme.space(6)

  Repeater {
    model: control.field.options || []
    delegate: Rectangle {
      id: chip
      required property var modelData
      readonly property bool isSelected: control.value === chip.modelData.value

      width: Math.max(Theme.space(34), chipText.implicitWidth + Theme.space(20))
      height: Theme.space(30)
      radius: Theme.radiusSmall
      color: chip.isSelected ? Theme.selected : (area.containsMouse ? Theme.hover : "transparent")
      border.width: 1
      border.color: chip.isSelected ? Theme.accent : Theme.line

      Label {
        id: chipText
        anchors.centerIn: parent
        text: chip.modelData.label || String(chip.modelData.value)
        wrapMode: Text.NoWrap
        font.pixelSize: Theme.font.bodySmall
        color: chip.isSelected ? Theme.foreground : Theme.muted
      }

      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.edited(chip.modelData.value)
      }
    }
  }
}
