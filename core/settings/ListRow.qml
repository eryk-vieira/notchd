import QtQuick
import QtQuick.Layouts
import ".."

// One row of a bordered list (NotchCatalog, ModuleCatalog): a title, a
// line under it and, when `openable`, a gear that opens what the row is
// about; clicking anywhere on the row does too. `note` shows instead of the
// gear; `removable` adds a trash can.
Item {
  id: row

  property string title: ""
  property string subtitle: ""
  property bool dim: false
  property bool openable: true
  property bool removable: false
  property string note: ""
  property bool first: false
  signal openRequested()
  signal removeRequested()

  implicitHeight: Theme.space(52)

  Rectangle {
    anchors.fill: parent
    anchors.margins: 1
    radius: Theme.radius - 1
    color: rowArea.containsMouse && row.openable ? Theme.hover : "transparent"
  }
  Rectangle {
    visible: !row.first
    width: parent.width
    height: 1
    color: Theme.line
  }
  MouseArea {
    id: rowArea
    anchors.fill: parent
    hoverEnabled: true
    enabled: row.openable
    cursorShape: Qt.PointingHandCursor
    onClicked: row.openRequested()
  }

  RowLayout {
    anchors.fill: parent
    anchors.leftMargin: Theme.space(14)
    anchors.rightMargin: Theme.space(8)
    spacing: Theme.space(6)

    ColumnLayout {
      Layout.fillWidth: true
      spacing: Theme.space(2)
      Label {
        Layout.fillWidth: true
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        text: row.title
        color: row.dim ? Theme.muted : Theme.foreground
      }
      Label {
        Layout.fillWidth: true
        role: "help"
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
        text: row.subtitle
        color: Theme.faint
      }
    }

    Label {
      visible: row.note !== ""
      Layout.rightMargin: Theme.space(6)
      role: "help"
      wrapMode: Text.NoWrap
      color: Theme.faint
      text: row.note
    }
    IconButton {
      visible: row.removable
      glyph: 0xF0A7A  // nf-md-trash_can_outline
      danger: true
      onClicked: row.removeRequested()
    }
    IconButton {
      visible: row.openable
      glyph: 0xF08BB  // nf-md-cog_outline
      onClicked: row.openRequested()
    }
  }
}
