import QtQuick
import Quickshell
import "core"
import "core/settings"
import "core/Position.js" as Position

// Deterministic offscreen scenarios, one PNG each: the settings window, and
// the notch on each screen edge with the real modules (media closed,
// activities closed, the volume OSD peeking, the notch open).
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
      default: 0, min: 0, max: 120, step: 1, unit: "px", help: "Room at the top of the screen, e.g. your bar's height." },
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
  // extra fields, config keys to set, the notch the window edits and whether
  // to scroll the page to its end. Or, with `edge`, the notch on
  // that edge instead of the settings window.
  readonly property var scenarios: [
    { name: "general-dark", page: "general", theme: root.dark, bar: true, fields: root.omarchyFields },
    { name: "general-light", page: "general", theme: root.light, bar: true, fields: root.omarchyFields },
    { name: "modules-dark", page: "modules", theme: root.dark, bar: true, fields: root.omarchyFields },
    { name: "appearance-omarchy-dark", page: "appearance", theme: root.dark, bar: true, fields: root.omarchyFields },
    { name: "general-notch-dark", page: "general", theme: root.dark, bar: true, fields: root.omarchyFields,
      config: { compactStyle: "notch", position: { edge: "left", offset: 0.3 } }, scrollTo: "end" },
    { name: "general-notches-dark", page: "general", theme: root.dark, bar: true, fields: root.omarchyFields,
      config: { notches: [{}, { id: "jobs", modules: ["activities"], position: { edge: "bottom", screen: "all" } }] },
      notch: 1 },
    { name: "modules-notches-light", page: "modules", theme: root.light, bar: true, fields: root.omarchyFields,
      config: { notches: [{}, { id: "jobs", modules: ["activities"], position: { edge: "bottom" } }] },
      notch: 1 },
    { name: "general-standalone-dark", page: "general", theme: root.dark, bar: false, fields: root.standaloneFields },
    { name: "appearance-standalone-light", page: "appearance", theme: root.light, bar: false, fields: root.standaloneFields },
    { name: "edge-top", edge: "top", theme: root.dark },
    { name: "edge-bottom", edge: "bottom", theme: root.dark },
    { name: "edge-left", edge: "left", theme: root.dark },
    { name: "edge-right", edge: "right", theme: root.light }
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
    barStyleAvailable: root.scenario ? !!root.scenario.bar : false
    hostSettingsSchema: root.scenario && root.scenario.fields ? root.scenario.fields : []
    settingsPage: root.scenario && root.scenario.page ? root.scenario.page : "general"
  }

  SettingsWindow { id: win; svc: svc }

  // ------------------------------------------------------------ notch
  // Real services with the real modules, the media one playing
  // demo-player.py's track: what each module shows on each edge.
  component DemoService: NotchService {
    property string tag: ""
    ipcTarget: "notchd-visual-" + tag
    configPath: root.outDir + "/edge-" + tag + ".json"
    barStyleAvailable: false
    hostModules: ({ osd: Qt.resolvedUrl("hosts/omarchy/modules/osd.qml") })
  }
  DemoService { id: mediaSvc; tag: "media"; defaultModules: ["media"] }
  DemoService { id: activitySvc; tag: "activity"; defaultModules: ["activities"] }
  DemoService { id: osdSvc; tag: "osd"; defaultModules: ["osd"] }
  DemoService { id: openSvc; tag: "open"; defaultModules: ["media", "activities"] }
  readonly property var demoServices: [mediaSvc, activitySvc, osdSvc, openSvc]

  // Once the modules are up: an activity on two of them, the volume OSD
  // held open, the last one pinned open.
  Timer {
    interval: 1500
    running: true
    onTriggered: {
      var deploy = JSON.stringify({ id: "deploy", icon: "󰜎", title: "Deploying api", subtitle: "staging · 3 of 5",
                                    progress: 64, sticky: true, peek: false })
      activitySvc.moduleById("activities").push(deploy)
      openSvc.moduleById("activities").push(deploy)
      osdSvc.moduleById("osd").show(JSON.stringify({ icon: "volume", value: "62", duration: "600000" }))
      openSvc.open()
    }
  }

  // A slice of a screen with the bar on top and a service's notch on it.
  component MockScreen: Rectangle {
    id: mock
    property var svc: null
    property string caption: ""
    readonly property int barHeight: Theme.space(22)
    width: Theme.space(500)
    height: Theme.space(330)
    color: Theme.mix(Theme.background, Theme.foreground, 0.12)
    border.width: 1
    border.color: Theme.line
    clip: true

    Rectangle { width: parent.width; height: mock.barHeight; color: Theme.background }
    Text {
      anchors.verticalCenter: parent.top
      anchors.verticalCenterOffset: mock.barHeight / 2
      x: Theme.space(10)
      text: mock.caption
      color: Theme.muted
      font.family: Theme.font.family
      font.pixelSize: Theme.font.caption
    }
    NotchCard {
      id: mockCard
      notch: mock.svc ? mock.svc.firstCopy : null
      maxWidth: mock.width - Theme.space(24)
      maxHeight: mock.height - Theme.space(24)
      readonly property var spot: Position.place({
        edge: mockCard.edge, offset: mockCard.notch ? mockCard.notch.placement.offset : 0.5,
        width: mock.width, height: mock.height, cardWidth: mockCard.width, cardHeight: mockCard.height,
        insets: Position.insets("top", mock.barHeight, true), margin: mockCard.shoulder + Theme.space(4)
      })
      x: mockCard.spot.x
      y: mockCard.spot.y
    }
  }

  FloatingWindow {
    id: notchWin
    visible: !!root.scenario && !!root.scenario.edge
    implicitWidth: notchScene.width
    implicitHeight: notchScene.height
    color: Theme.background
    Grid {
      id: notchScene
      columns: 2
      padding: Theme.space(16)
      spacing: Theme.space(16)
      MockScreen { svc: mediaSvc; caption: "media, compact" }
      MockScreen { svc: activitySvc; caption: "activities, compact" }
      MockScreen { svc: osdSvc; caption: "osd, peek" }
      MockScreen { svc: openSvc; caption: "expanded" }
    }
  }

  // Set a scenario, give it a beat to lay out (and the notch to settle),
  // grab, then the next.
  function next() {
    root.index++
    if (!root.scenario) { quitTimer.start(); return }
    Theme.provider = root.scenario.theme
    svc.setConfigValue("workspaces", root.scenario.bar ? [1, 2, 3] : undefined)
    var cfg = root.scenario.config || {}
    svc.setConfigValue("compactStyle", cfg.compactStyle)
    svc.setConfigValue("position", cfg.position)
    svc.setConfigValue("notches", cfg.notches)
    svc.settingsNotch = root.scenario.notch || 0
    for (var i = 0; i < root.demoServices.length; i++)
      root.demoServices[i].setConfigValue("position", root.scenario.edge ? { edge: root.scenario.edge } : undefined)
    grabTimer.interval = root.scenario.edge ? 1200 : 400
    grabTimer.start()
    scrollTimer.start()
  }

  Timer { interval: 600; running: true; onTriggered: root.next() }
  Timer {
    id: grabTimer
    interval: 400
    onTriggered: {
      var name = root.scenario.name
      var target = root.scenario.edge ? notchScene : win.contentItem.children[0]
      target.grabToImage(function(result) {
        if (!result.saveToFile(root.outDir + "/" + name + ".png")) console.warn("could not save " + name)
        root.next()
      })
    }
  }
  // After the page lays out, before the grab.
  Timer {
    id: scrollTimer
    interval: 200
    onTriggered: if (root.scenario) win.pageView.contentY = root.scenario.scrollTo === "end"
      ? Math.max(0, win.pageView.contentHeight - win.pageView.height) : 0
  }
  Timer { id: quitTimer; interval: 100; onTriggered: Qt.quit() }
}
