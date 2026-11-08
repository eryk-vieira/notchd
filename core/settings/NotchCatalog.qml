import QtQuick
import QtQuick.Layouts
import ".."
import "Settings.js" as Settings

// `notches` field: a row per notch, in the order navigation numbers them,
// each with its number, where it is and what it shows, and a gear that opens
// its page ("notch/<index>", by its place in the config), and Add. Add asks
// the daemon for a new notch (NotchService.addNotch: its rule picks the
// screen and the spot) and opens its page; the trash can takes a notch out
// (not the last one that shows at rest), and with one left the config goes
// back to its top-level keys; a notch the host declares goes by a note in the
// config. The list is edited through the service rather than `edited(value)`.
// A notch without decoration says so under its name.
ColumnLayout {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var notches: control.svc ? control.svc.orderedNotches : []
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
          title: (entry.modelData.navNumber > 0 ? entry.modelData.navNumber + "  " : "") + entry.modelData.notchId
          subtitle: Settings.notchSummary({
            edge: entry.modelData.edge,
            moduleIds: entry.modelData.moduleIds
          }, control.titles) + (entry.modelData.decoration ? "" : " · only while it peeks")
          // The daemon keeps the last notch that shows at rest.
          removable: control.notches.some(function(n) { return n !== entry.modelData && n.decoration })
          onOpenRequested: control.open(entry.modelData.index)
          onRemoveRequested: if (control.svc) control.svc.removeNotch(entry.modelData.notchId)
        }
      }
    }
  }

  Button {
    icon: 0xF0415  // nf-md-plus
    text: "Add notch"
    onClicked: if (control.svc) control.svc.addNotch(function(index) { if (index >= 0) control.open(index) })
  }
}
