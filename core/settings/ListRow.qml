import QtQuick
import QtQuick.Layouts
import ".."

// One row of a bordered list (NotchCatalog, ModuleCatalog): a title, a
// line under it and, when `openable`, a gear that opens what the row is
// about; clicking anywhere on the row does too. `note` shows instead of the
// gear; `removable` adds a trash can (with `confirmRemove`, the first click
// arms it and the second removes: it disarms after a few seconds). `badges`
// are small tags before the buttons, `detail` a third line (a folder), and
// `folder` adds a button that opens it (`folderRequested`).
Item {
  id: row

  property string title: ""
  property string subtitle: ""
  property bool dim: false
  property bool openable: true
  property bool removable: false
  property bool confirmRemove: false
  property bool armed: false
  property string note: ""
  property var badges: []
  property string detail: ""
  property bool warn: false
  property bool folder: false
  property bool first: false
  signal openRequested()
  signal removeRequested()
  signal folderRequested()

  implicitHeight: Theme.space(52) + (row.detail !== "" ? Theme.space(16) : 0)

  Timer {
    id: disarm
    interval: 4000
    onTriggered: row.armed = false
  }
  function askRemove() {
    if (!row.confirmRemove || row.armed) {
      row.armed = false
      disarm.stop()
      row.removeRequested()
      return
    }
    row.armed = true
    disarm.restart()
  }

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
        color: row.warn ? Theme.danger : Theme.faint
      }
      Label {
        visible: row.detail !== ""
        Layout.fillWidth: true
        role: "help"
        wrapMode: Text.NoWrap
        elide: Text.ElideMiddle
        text: row.detail
        color: Theme.faint
      }
    }

    Row {
      visible: row.badges.length > 0
      spacing: Theme.space(4)
      Repeater {
        model: row.badges
        delegate: Rectangle {
          id: badge
          required property string modelData
          width: tag.implicitWidth + Theme.space(10)
          height: tag.implicitHeight + Theme.space(2)
          radius: Theme.radiusSmall
          color: "transparent"
          border.width: 1
          border.color: Theme.line
          Label {
            id: tag
            anchors.centerIn: parent
            role: "help"
            wrapMode: Text.NoWrap
            text: badge.modelData
          }
        }
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
      visible: row.folder
      glyph: 0xF0770  // nf-md-folder_open_outline
      onClicked: row.folderRequested()
    }
    Label {
      visible: row.removable && row.armed
      role: "help"
      wrapMode: Text.NoWrap
      color: Theme.danger
      text: "Delete it? Click again"
    }
    IconButton {
      visible: row.removable
      glyph: 0xF0A7A  // nf-md-trash_can_outline
      danger: true
      onClicked: row.askRemove()
    }
    IconButton {
      visible: row.openable
      glyph: 0xF08BB  // nf-md-cog_outline
      onClicked: row.openRequested()
    }
  }
}
