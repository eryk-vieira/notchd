import QtQuick
import ".."

// `boolean` field: a switch.
Rectangle {
  id: control

  property var field: ({})
  property var value
  // Plain use, outside a field row.
  property bool checked: control.value === true
  signal edited(var value)

  implicitWidth: Theme.space(38)
  implicitHeight: Theme.space(22)
  radius: height / 2
  color: control.checked ? Theme.accent : Theme.selected
  border.width: control.checked ? 0 : 1
  border.color: Theme.line
  Behavior on color { ColorAnimation { duration: 120 } }

  Rectangle {
    width: control.height - Theme.space(6)
    height: width
    radius: width / 2
    anchors.verticalCenter: parent.verticalCenter
    x: control.checked ? control.width - width - Theme.space(3) : Theme.space(3)
    color: control.checked ? Theme.background : Theme.foreground
    Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: control.edited(!control.checked)
  }
}
