import QtQuick
import ".."
import "Settings.js" as Settings

// `workspaces` field: a chip per workspace (1 to 10, the ones the compositor
// knows, the ones picked); clicking one picks or drops it. None picked
// removes the key: every workspace.
Flow {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var picked: Settings.toList(control.value).map(Settings.workspaceValue)
  readonly property var known: control.svc && control.svc.compositor ? control.svc.compositor.knownWorkspaces : []
  readonly property var choices: Settings.workspaceChoices(control.known, control.picked)

  function toggle(w) { control.edited(Settings.toggleWorkspace(control.picked, w)) }

  spacing: Theme.space(6)

  Repeater {
    model: control.choices
    delegate: Rectangle {
      id: chip
      required property var modelData
      readonly property bool isOn: control.picked.indexOf(modelData) !== -1

      width: Math.max(Theme.space(34), chipText.implicitWidth + Theme.space(20))
      height: Theme.space(30)
      radius: Theme.radiusSmall
      color: chip.isOn ? Theme.selected : (area.containsMouse ? Theme.hover : "transparent")
      border.width: 1
      border.color: chip.isOn ? Theme.accent : Theme.line

      Label {
        id: chipText
        anchors.centerIn: parent
        text: String(chip.modelData)
        wrapMode: Text.NoWrap
        font.pixelSize: Theme.font.bodySmall
        color: chip.isOn ? Theme.foreground : Theme.muted
      }

      MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: control.toggle(chip.modelData)
      }
    }
  }
}
