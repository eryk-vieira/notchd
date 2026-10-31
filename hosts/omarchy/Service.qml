import QtQuick
import qs.Commons
import "../../core"

// Omarchy host: the notch service as an Omarchy shell plugin. Wires the core
// to Omarchy: its IPC name, the osd module that receives `omarchy osd`, the
// bar indicator (so compactStyle "bar" works), Hyprland (for workspaces) and
// Omarchy's theme.
NotchService {
  id: svc

  // Injected by the Omarchy shell.
  property var shell: null

  ipcTarget: "eryk.notchd"
  logName: "eryk.notchd"
  barStyleAvailable: true
  compositor: hyprland
  defaultModules: ["osd", "media", "activities"]
  hostModules: ({
    osd: Qt.resolvedUrl("modules/osd.qml")
  })
  hostSettingsSchema: [
    { page: "appearance", section: "Theme", type: "note", label: "Follows your Omarchy theme",
      help: "Colors, fonts and spacing come from the active Omarchy theme and change with it." }
  ]

  HyprlandCompositor { id: hyprland }

  // Omarchy's theme mapped onto the core's tokens; follows theme switches.
  QtObject {
    id: omarchyTheme
    readonly property color foreground: Color.foreground
    readonly property color background: Color.background
    readonly property color accent: Color.accent
    readonly property color danger: Color.urgent
    readonly property string fontFamily: Style.font.family
    readonly property int fontCaption: Style.font.caption
    readonly property int fontBodySmall: Style.font.bodySmall
    readonly property int fontBody: Style.font.body
    readonly property int fontHeading: Style.font.heading
    readonly property int fontDisplay: Style.font.display
    readonly property real spacingScale: Style.effectiveSpacingScale
  }

  Component.onCompleted: Theme.provider = omarchyTheme
}
