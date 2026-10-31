import QtQuick
import QtQuick.Layouts
import ".."
import "Settings.js" as Settings

// `notches` field: a row per notch, where it is and what it shows, with a
// gear that opens its page ("notch/<index>"), and Add. Add makes a new
// notch (NotchService.addNotch) and opens its page; the trash can (with
// more than one) takes a notch out, and with one left the config goes back
// to its top-level keys. The list is edited through the service rather than
// `edited(value)`: a new notch needs a free id and edge, and removing one
// moves its keys.
ColumnLayout {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var notches: control.svc ? control.svc.notches : []
  readonly property var titles: {
    var out = {}
    var catalog = control.svc ? control.svc.moduleCatalog : []
    for (var i = 0; i < catalog.length; i++) out[catalog[i].moduleId] = catalog[i].title
    return out
  }

  function open(index) {
    if (!control.svc) return
    control.svc.settingsNotch = index
    control.svc.settingsPage = Settings.notchPageId(index)
  }

  spacing: Theme.space(12)

  Rectangle {
    Layout.fillWidth: true
    implicitHeight: list.implicitHeight
    radius: Theme.radius
    color: "transparent"
    border.width: 1
    border.color: Theme.line

    Column {
      id: list
      width: parent.width

      Repeater {
        model: control.notches
        delegate: ListRow {
          id: entry
          required property var modelData
          required property int index

          width: list.width
          first: entry.index === 0
          title: entry.modelData.notchId
          subtitle: Settings.notchSummary({
            edge: entry.modelData.edge,
            compactStyle: entry.modelData.compactStyle,
            moduleIds: entry.modelData.moduleIds
          }, control.titles)
          removable: control.notches.length > 1
          onOpenRequested: control.open(entry.modelData.index)
          onRemoveRequested: if (control.svc) control.svc.removeNotch(entry.modelData.index)
        }
      }
    }
  }

  Button {
    icon: 0xF0415  // nf-md-plus
    text: "Add notch"
    onClicked: if (control.svc) control.open(control.svc.addNotch())
  }
}
