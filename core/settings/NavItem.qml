import QtQuick
import QtQuick.Layouts
import ".."

// One page in the sidebar.
Rectangle {
  id: item

  property var icon: ""
  property string label: ""
  property bool current: false
  signal activated()

  implicitHeight: Theme.space(34)
  radius: Theme.radiusSmall
  color: item.current ? Theme.selected : (area.containsMouse ? Theme.hover : "transparent")

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.space(10)
    anchors.rightMargin: Theme.space(10)
    spacing: Theme.space(10)
    Icon {
      Layout.preferredWidth: Theme.space(18)
      glyph: item.icon
      size: Theme.font.body + 2
      color: item.current ? Theme.foreground : Theme.muted
    }
    Label {
      Layout.fillWidth: true
      text: item.label
      wrapMode: Text.NoWrap
      elide: Text.ElideRight
      color: item.current ? Theme.foreground : Theme.muted
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    onClicked: item.activated()
  }
}
