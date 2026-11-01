import QtQuick
import ".."
import "Settings.js" as Settings

// `moduleCatalog` field: one list of the modules the host can load, the
// field's `part` (Settings.moduleKind): "notch" (notches show them),
// "agent" (coding agents) or "standalone" (a place of their own);
// where (or whether) each shows, and a gear that opens its own page
// ("modules/<id>") when it has settings, loaded or not. Edits nothing
// itself.
Rectangle {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var modules: control.svc ? Settings.catalogPart(control.svc.moduleCatalog, control.field.part) : []
  readonly property var schema: control.svc ? control.svc.settingsSchema : []

  function hasPage(id) {
    var page = Settings.modulePageId(id)
    return control.schema.some(function(f) { return Settings.pageOf(f) === page })
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
      model: control.modules
      delegate: ListRow {
        id: entry
        required property var modelData
        required property int index
        readonly property string status: control.svc
          ? Settings.moduleStatus(modelData.moduleId, control.svc.notchSpecs, modelData.standalone,
                                  control.svc.standaloneEnabled(modelData.moduleId)) : ""

        width: list.width
        first: entry.index === 0
        title: entry.modelData.title
        subtitle: entry.modelData.moduleId + " · " + entry.status
        dim: /off$/i.test(entry.status)
        openable: control.hasPage(entry.modelData.moduleId)
        note: entry.openable ? "" : "No settings"
        onOpenRequested: if (control.svc) control.svc.settingsPage = Settings.modulePageId(entry.modelData.moduleId)
      }
    }
  }
}
