import QtQuick
import QtQuick.Layouts
import ".."

// A plain outlined button.
Rectangle {
  id: button

  property string text: ""
  property var icon: ""
  signal clicked()

  implicitHeight: Theme.space(32)
  implicitWidth: row.implicitWidth + Theme.space(24)
  radius: Theme.radiusSmall
  color: area.pressed ? Theme.selected : (area.containsMouse ? Theme.hover : "transparent")
  border.width: 1
  border.color: Theme.line

  RowLayout {
    id: row
    anchors.centerIn: parent
    spacing: Theme.space(8)
    Icon {
      visible: !!button.icon
      glyph: button.icon
      size: Theme.font.body
      color: Theme.muted
    }
    Label {
      text: button.text
      wrapMode: Text.NoWrap
      font.pixelSize: Theme.font.bodySmall
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
