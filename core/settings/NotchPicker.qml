import QtQuick
import QtQuick.Layouts
import ".."

// `notches` field: a chip per notch, the one the window edits raised;
// picking another shows its keys below it, on the Notches page. Add makes
// a new notch (NotchService.addNotch) and picks it; Remove takes the picked
// one out, and with one left the config goes back to its top-level keys.
// The list is edited through the service rather than `edited(value)`: a new
// notch needs a free id and edge, and removing one moves its keys.
ColumnLayout {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var notches: control.svc ? control.svc.notches : []
  readonly property int selected: control.svc && control.svc.settingsNotchObject
    ? control.svc.settingsNotchObject.index : 0

  spacing: Theme.space(10)

  Flow {
    Layout.fillWidth: true
    spacing: Theme.space(6)

    Repeater {
      model: control.notches
      delegate: Rectangle {
        id: chip
        required property var modelData
        readonly property bool isOn: modelData.index === control.selected

        width: Math.max(Theme.space(64), chipText.implicitWidth + Theme.space(24))
        height: Theme.space(30)
        radius: Theme.radiusSmall
        color: chip.isOn ? Theme.selected : (area.containsMouse ? Theme.hover : "transparent")
        border.width: 1
        border.color: chip.isOn ? Theme.accent : Theme.line

        Label {
          id: chipText
          anchors.centerIn: parent
          text: chip.modelData.notchId
          wrapMode: Text.NoWrap
          font.pixelSize: Theme.font.bodySmall
          color: chip.isOn ? Theme.foreground : Theme.muted
        }

        MouseArea {
          id: area
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onClicked: if (control.svc) control.svc.settingsNotch = chip.modelData.index
        }
      }
    }
  }

  RowLayout {
    spacing: Theme.space(8)
    Button {
      icon: 0xF0415  // nf-md-plus
      text: "Add notch"
      onClicked: if (control.svc) control.svc.settingsNotch = control.svc.addNotch()
    }
    Button {
      visible: control.notches.length > 1
      icon: 0xF0A7A  // nf-md-trash_can_outline
      text: "Remove " + (control.svc && control.svc.settingsNotchObject ? control.svc.settingsNotchObject.notchId : "")
      onClicked: {
        if (!control.svc) return
        var at = control.selected
        control.svc.removeNotch(at)
        control.svc.settingsNotch = Math.max(0, at - 1)
      }
    }
  }
}
