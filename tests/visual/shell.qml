import QtQuick
import Quickshell
import "core"
import "core/settings"

// Deterministic offscreen scenarios for the settings window, one PNG each.
// scripts/visual-test.sh links the core next to this file, points
// NOTCHD_VISUAL_DIR at an empty scratch dir and runs it with Qt's offscreen
// backend. The config lives in that scratch dir, never in ~/.config.
ShellRoot {
  id: root

  readonly property string outDir: Quickshell.env("NOTCHD_VISUAL_DIR")

  readonly property var dark: ({ foreground: "#cacccc", background: "#101315", accent: "#7aa2f7" })
  readonly property var light: ({ foreground: "#2a2b30", background: "#f6f5f1", accent: "#3b6fd8" })

  // What the standalone host adds, so its pages have content.
  readonly property var standaloneFields: [
    { page: "general", section: "Layout", key: "topOffset", type: "integer", label: "Top offset",
      default: 0, min: 0, max: 120, step: 1, unit: "px", help: "Gap above the notch, e.g. your bar's height." },
    { page: "appearance", section: "Colors", key: "theme.foreground", type: "color", label: "Foreground", default: "#cacccc" },
    { page: "appearance", section: "Colors", key: "theme.accent", type: "color", label: "Accent",
      help: "Defaults to the foreground color." },
    { page: "appearance", section: "Text", key: "theme.fontFamily", type: "string", label: "Font", default: "monospace" }
  ]
  // What the Omarchy host adds.
  readonly property var omarchyFields: [
    { page: "appearance", section: "Theme", type: "note", label: "Follows your Omarchy theme",
      help: "Colors, fonts and spacing come from the active Omarchy theme and change with it." }
  ]

  // Each scenario: the page, the theme, whether the host has a bar and its
  // extra fields.
  readonly property var scenarios: [
    { name: "general-dark", page: "general", theme: root.dark, bar: true, fields: root.omarchyFields },
    { name: "general-light", page: "general", theme: root.light, bar: true, fields: root.omarchyFields },
    { name: "modules-dark", page: "modules", theme: root.dark, bar: true, fields: root.omarchyFields },
    { name: "appearance-omarchy-dark", page: "appearance", theme: root.dark, bar: true, fields: root.omarchyFields },
    { name: "general-standalone-dark", page: "general", theme: root.dark, bar: false, fields: root.standaloneFields },
    { name: "appearance-standalone-light", page: "appearance", theme: root.light, bar: false, fields: root.standaloneFields }
  ]
  property int index: -1
  readonly property var scenario: index >= 0 && index < scenarios.length ? scenarios[index] : null

  // A compositor with workspaces, so the workspaces field shows; the Omarchy
  // scenarios pick 1 to 3, as a config would.
  QtObject {
    id: fakeCompositor
    readonly property string focusedScreenName: ""
    function hasFullscreen(screen) { return false }
    readonly property bool supportsWorkspaces: true
    readonly property var knownWorkspaces: ["1", "2", "4", "code"]
    function activeWorkspace(screen) { return null }
  }

  NotchService {
    id: svc
    ipcTarget: "notchd-visual"
    compositor: fakeCompositor
    configPath: root.outDir + "/config.json"
    barStyleAvailable: root.scenario ? root.scenario.bar : false
    hostSettingsSchema: root.scenario ? root.scenario.fields : []
    settingsPage: root.scenario ? root.scenario.page : "general"
  }

  SettingsWindow { id: win; svc: svc }

  // Set a scenario, give it a beat to lay out, grab, then the next.
  function next() {
    root.index++
    if (!root.scenario) { quitTimer.start(); return }
    Theme.provider = root.scenario.theme
    svc.setConfigValue("workspaces", root.scenario.bar ? [1, 2, 3] : undefined)
    grabTimer.start()
  }

  Timer { interval: 600; running: true; onTriggered: root.next() }
  Timer {
    id: grabTimer
    interval: 400
    onTriggered: {
      var name = root.scenario.name
      win.contentItem.children[0].grabToImage(function(result) {
        if (!result.saveToFile(root.outDir + "/" + name + ".png")) console.warn("could not save " + name)
        root.next()
      })
    }
  }
  Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }
}
