import QtQuick
import ".."

// A square button showing just a glyph (a gear, a trash can).
Rectangle {
  id: button

  property var glyph: ""
  // Danger tint on hover, for removing things.
  property bool danger: false
  signal clicked()

  implicitWidth: Theme.space(32)
  implicitHeight: Theme.space(32)
  radius: Theme.radiusSmall
  color: area.pressed ? Theme.selected : (area.containsMouse ? Theme.hover : "transparent")

  Icon {
    anchors.centerIn: parent
    glyph: button.glyph
    size: Theme.font.heading
    color: area.containsMouse ? (button.danger ? Theme.danger : Theme.foreground) : Theme.muted
  }
  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: button.clicked()
  }
}
