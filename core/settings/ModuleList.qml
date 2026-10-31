import QtQuick
import QtQuick.Layouts
import ".."
import "Settings.js" as Settings

// `modules` field: every module the host can load, enabled ones first and in
// order. The switch loads or unloads one; the arrows reorder enabled ones.
Rectangle {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var enabledIds: Settings.toList(control.value)
  readonly property var available: control.svc ? Settings.toList(control.svc.availableModuleIds) : []
  readonly property var all: Settings.allIds(control.enabledIds, control.available)

  function toggle(id) { control.edited(Settings.toggleId(control.enabledIds, id)) }
  function move(id, delta) { control.edited(Settings.moveId(control.enabledIds, id, delta)) }
  // A loaded module's own title; unloaded ones only have their id.
  function titleOf(id) {
    var m = control.svc ? control.svc.moduleById(id) : null
    return m && m.title ? m.title : id.charAt(0).toUpperCase() + id.slice(1)
  }

  implicitHeight: list.implicitHeight
  radius: Theme.radius
  color: "transparent"
  border.width: 1
  border.color: Theme.line

  Column {
    id: list
    width: parent.width

    Repeater {
      model: control.all
      delegate: Item {
        id: entry
        required property string modelData
        required property int index
        readonly property int position: control.enabledIds.indexOf(modelData)
        readonly property bool isOn: position !== -1
        readonly property bool known: control.available.indexOf(modelData) !== -1

        width: list.width
        implicitHeight: Theme.space(52)

        Rectangle {
          visible: entry.index > 0
          width: parent.width
          height: 1
          color: Theme.line
        }

        RowLayout {
          anchors.fill: parent
          anchors.leftMargin: Theme.space(14)
          anchors.rightMargin: Theme.space(14)
          spacing: Theme.space(12)

          ColumnLayout {
            Layout.fillWidth: true
            spacing: Theme.space(2)
            Label {
              Layout.fillWidth: true
              wrapMode: Text.NoWrap
              elide: Text.ElideRight
              text: control.titleOf(entry.modelData)
              color: entry.isOn ? Theme.foreground : Theme.muted
            }
            Label {
              Layout.fillWidth: true
              role: "help"
              wrapMode: Text.NoWrap
              text: entry.known ? entry.modelData : entry.modelData + " · not found"
              color: entry.known ? Theme.faint : Theme.danger
            }
          }

          Repeater {
            model: entry.isOn ? [-1, 1] : []
            delegate: Icon {
              required property int modelData
              readonly property bool usable: modelData < 0 ? entry.position > 0
                : entry.position < control.enabledIds.length - 1
              glyph: modelData < 0 ? 0xF0143 : 0xF0140  // nf-md-chevron_up / _down
              size: Theme.font.heading
              color: usable ? (arrowArea.containsMouse ? Theme.foreground : Theme.muted) : Theme.line
              MouseArea {
                id: arrowArea
                anchors.fill: parent
                anchors.margins: -Theme.space(4)
                hoverEnabled: true
                enabled: parent.usable
                cursorShape: Qt.PointingHandCursor
                onClicked: control.move(entry.modelData, parent.modelData)
              }
            }
          }

          Toggle {
            Layout.leftMargin: Theme.space(4)
            checked: entry.isOn
            onEdited: control.toggle(entry.modelData)
          }
        }
      }
    }
  }
}
