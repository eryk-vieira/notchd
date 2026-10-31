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
// Config: $NOTCHD_CONFIG if set, else $XDG_CONFIG_HOME/notchd/config.json.
ShellRoot {
  id: shell

  readonly property var config: svc.config || ({})
  readonly property var themeConfig: shell.config.theme || ({})

  NotchService {
    id: svc
    ipcTarget: "notchd"
    logName: "notchd"
    configPath: Quickshell.env("NOTCHD_CONFIG") || svc.defaultConfigPath
    hostSettingsSchema: [
      { section: "Layout", key: "topOffset", type: "integer", label: "Top offset",
        default: 0, min: 0, max: 120, step: 1, unit: "px",
        help: "Gap above the notch, e.g. your bar's height." },
      { section: "Appearance", key: "theme.foreground", type: "color", label: "Foreground", default: "#cacccc" },
      { section: "Appearance", key: "theme.background", type: "color", label: "Background", default: "#101315" },
      { section: "Appearance", key: "theme.accent", type: "color", label: "Accent",
        help: "Defaults to the foreground color." },
      { section: "Appearance", key: "theme.fontFamily", type: "string", label: "Font", default: "monospace",
        help: "Use a Nerd Font so module icons render." }
    ]
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
