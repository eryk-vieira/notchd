import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import ".."
import "Settings.js" as Settings

// `moduleCatalog` field: one list of the modules the host can load, the
// field's `part` (Settings.moduleKind): "notch" (notches show them),
// "agent" (coding agents) are the built-in ones; "user" is yours: every
// custom module, whatever it is (a
// folder of `modules/` with a process, a terminal or both). Each row says
// where (or whether) the module shows, and a gear opens its own page
// ("modules/<id>") when it has settings, loaded or not. A custom module's
// row also has its parts as badges, its folder (with a button to open it),
// the permissions its manifest declares, its error if it has one, and a
// trash can that asks twice before the daemon deletes the module (folder,
// settings, place in every notch). The list also adds a terminal, through
// the service (NotchService.addTerminal): Add opens the new one's page.
ColumnLayout {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property var modules: control.svc ? Settings.catalogPart(control.svc.moduleCatalog, control.field.part) : []
  readonly property var schema: control.svc ? control.svc.settingsSchema : []
  readonly property bool yours: control.field.part === "user"

  function hasPage(id) {
    var page = Settings.modulePageId(id)
    return control.schema.some(function(f) { return Settings.pageOf(f) === page })
  }
  // What a custom module has: its process, its terminal.
  function badgesOf(m) {
    var out = []
    if (m.process) out.push("process")
    if (m.terminal) out.push("terminal")
    return out
  }
  // The module's own error (a crash, a bad module.json), when it has one.
  function errorOf(id) {
    var m = control.svc && control.svc.client ? control.svc.client.modules[id] : null
    return m && m.error ? String(m.error) : ""
  }
  function detailOf(m) {
    var parts = []
    if (m.dir) parts.push(m.dir)
    if (m.permissions && m.permissions.length > 0) parts.push("permissions: " + m.permissions.join(", "))
    return parts.join("  \u00b7  ")
  }

  // Opens a custom module's folder in the file manager.
  Process {
    id: openFolder
    property string dir: ""
    command: ["xdg-open", openFolder.dir]
  }

  spacing: Theme.space(12)

  Rectangle {
    visible: control.modules.length > 0
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
        model: control.modules
        delegate: ListRow {
          id: entry
          required property var modelData
          required property int index
          readonly property string status: control.svc
            ? Settings.moduleStatus(modelData.moduleId, control.svc.notchSpecs) : ""
          readonly property string error: control.yours ? control.errorOf(modelData.moduleId) : ""

          width: list.width
          first: entry.index === 0
          title: entry.modelData.title
          subtitle: entry.modelData.moduleId + " \u00b7 " + (entry.error !== "" ? "error: " + entry.error : entry.status)
          warn: entry.error !== ""
          dim: /off$/i.test(entry.status)
          badges: control.yours ? control.badgesOf(entry.modelData) : []
          detail: control.yours ? control.detailOf(entry.modelData) : ""
          folder: control.yours && !!entry.modelData.dir
          openable: control.hasPage(entry.modelData.moduleId)
          note: entry.openable ? "" : "No settings"
          removable: control.yours
          confirmRemove: true
          onOpenRequested: if (control.svc) control.svc.settingsPage = Settings.modulePageId(entry.modelData.moduleId)
          onFolderRequested: {
            openFolder.dir = entry.modelData.dir
            openFolder.running = true
          }
          onRemoveRequested: if (control.svc) control.svc.removeModule(entry.modelData.moduleId)
        }
      }
    }
  }

  Label {
    visible: control.yours && control.modules.length === 0
    Layout.fillWidth: true
    role: "help"
    text: "None yet."
  }

  Button {
    visible: control.yours
    icon: 0xF0415  // nf-md-plus
    text: "Add terminal"
    onClicked: if (control.svc) control.svc.addTerminal(function(id) {
      if (control.svc) control.svc.settingsPage = Settings.modulePageId(id)
    })
  }

  Label {
    visible: control.yours
    Layout.fillWidth: true
    role: "help"
    text: "A module with a program of its own, or a terminal and a program together, is a folder with a module.json: docs/modules.md."
  }
}
