import QtQuick
import Quickshell
import "core"

// Standalone host: the notch as its own Quickshell config, for any Wayland
// compositor with layer-shell. Run it with `qs -p <this directory>`.
//
// No desktop shell to lean on, so: no bar indicator (compactStyle is always
// "notch"), the theme comes from the config's "theme" object, and the gap
// above the notch (e.g. your bar's height) from "topOffset".
//
// Config: $NOTCHD_CONFIG if set, else config.json next to this file.
ShellRoot {
  id: shell

  readonly property string dir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  readonly property string configPath: Quickshell.env("NOTCHD_CONFIG") || (shell.dir + "/config.json")
  readonly property var config: svc.config || ({})
  readonly property var themeConfig: shell.config.theme || ({})

  NotchService {
    id: svc
    ipcTarget: "notchd"
    logName: "notchd"
    configPath: shell.configPath
  }

  QtObject {
    id: configTheme
    readonly property var foreground: shell.themeConfig.foreground
    readonly property var background: shell.themeConfig.background
    readonly property var accent: shell.themeConfig.accent
    readonly property var fontFamily: shell.themeConfig.fontFamily
    readonly property var spacingScale: shell.themeConfig.spacingScale
  }
  Component.onCompleted: Theme.provider = configTheme

  readonly property bool onHyprland: !!Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE")
  Loader {
    id: compositor
    sourceComponent: shell.onHyprland ? hyprlandAdapter : genericAdapter
  }
  Component { id: hyprlandAdapter; HyprlandCompositor {} }
  Component { id: genericAdapter; GenericCompositor {} }

  NotchSurface {
    svc: svc
    compositor: compositor.item
    barHeight: Math.max(0, Number(shell.config.topOffset) || 0)
  }
}
