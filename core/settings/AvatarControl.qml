import QtQuick
import QtQuick.Layouts
import QtQuick.Dialogs
import ".."
import "../Avatar.js" as Avatar
import "Settings.js" as Settings

// The `avatar` field: an agent's face, made from a photo. A preview the
// size of an open notch, alive (AvatarView), then Choose photo… (a file
// dialog), Test speech and Remove, and how making one goes. The field's
// key is "<id>.avatar" (Avatar.ownerOf); its value the avatar's folder.
// Making and removing go through the service (NotchService.createAvatar,
// removeAvatar), which sets the key itself once the files are there, so
// this control never emits `edited`.
ColumnLayout {
  id: control

  property var field: ({})
  property var value
  property var svc: null
  signal edited(var value)

  readonly property string owner: Avatar.ownerOf(control.field.key)
  readonly property var job: control.svc && control.owner !== "" ? control.svc.avatarJobs[control.owner] : null
  readonly property bool running: !!control.job && !!control.job.running
  readonly property bool hasAvatar: typeof control.value === "string" && control.value !== ""
  readonly property string status: Avatar.statusText(control.job)
  readonly property string title: control.svc ? Settings.moduleTitle(control.owner, control.svc.moduleInfo[control.owner]) : control.owner
  property bool testing: false
  // The preview (the QML tests read it).
  readonly property alias view: preview

  spacing: Theme.space(10)

  Rectangle {
    Layout.fillWidth: true
    Layout.preferredHeight: Theme.space(230)
    radius: Theme.radius
    color: Theme.mix(Theme.background, "black", 0.35)
    border.width: 1
    border.color: Theme.line
    clip: true

    AvatarView {
      id: preview
      anchors.fill: parent
      anchors.margins: 1
      dir: control.hasAvatar ? control.value : ""
      version: control.svc ? (control.svc.avatarVersions[control.owner] || 0) : 0
      name: control.title
      colors: (control.svc && control.svc.moduleSetting(control.owner, "avatarColors")) || "theme"
      style: (control.svc && control.svc.moduleSetting(control.owner, "avatarStyle")) || "blocks"
      cellWidth: Theme.space(Number(control.svc && control.svc.moduleSetting(control.owner, "avatarCell")) || 7)
      speaking: control.testing
    }

    Label {
      anchors.centerIn: parent
      visible: !preview.ready
      role: "help"
      wrapMode: Text.NoWrap
      text: control.running ? control.status
        : control.hasAvatar ? "The avatar's files are missing: choose the photo again."
        : "No avatar yet"
    }
  }

  RowLayout {
    Layout.fillWidth: true
    spacing: Theme.space(8)

    Button {
      text: control.hasAvatar ? "Change photo…" : "Choose photo…"
      icon: 0xF02E9  // nf-md-image
      enabled: !control.running
      opacity: enabled ? 1 : 0.5
      onClicked: dialog.open()
    }
    Button {
      visible: preview.ready
      text: control.testing ? "Stop" : "Test speech"
      icon: control.testing ? 0xF04DB : 0xF040A  // nf-md-stop, nf-md-play
      onClicked: control.testing = !control.testing
    }
    Button {
      visible: control.hasAvatar && !control.running
      text: "Remove"
      icon: 0xF0A7A  // nf-md-trash_can_outline
      onClicked: { control.testing = false; control.svc.removeAvatar(control.owner) }
    }
    Item { Layout.fillWidth: true }
  }

  Label {
    Layout.fillWidth: true
    visible: control.status !== "" && !(control.running && !preview.ready)
    role: "help"
    text: control.status
    color: control.job && control.job.error ? Theme.danger : Theme.muted
  }

  FileDialog {
    id: dialog
    title: "A photo for " + control.title + "'s avatar"
    nameFilters: ["Photos (*.jpg *.jpeg *.png *.webp)", "All files (*)"]
    onAccepted: {
      var path = Avatar.localPath(String(dialog.selectedFile), "")
      if (path !== "" && control.svc) control.svc.createAvatar(control.owner, path)
    }
  }
}
