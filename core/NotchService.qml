import QtQuick
import Quickshell
import Quickshell.Io

// The notch's single source of truth: config, modules, mode, peeks, hover and
// IPC. Every surface that shows the notch (NotchSurface, a host's bar
// indicator) reads it; modules see it as `notch`.
//
// It knows nothing about the desktop it runs in. A host instantiates it and
// sets the properties in the "host" block below.
Item {
  id: svc
  visible: false

  // ------------------------------------------------------------------ host
  // IPC target scripts call (`qs ipc call <target> push ...`).
  property string ipcTarget: "notchd"
  // Absolute path of the JSON config. Watched; edits apply live.
  property string configPath: ""
  // Extra modules the host ships, as { id: url }. They win over built-ins
  // with the same id.
  property var hostModules: ({})
  // Whether the host has a bar indicator that can hold the compact state.
  // Without one, compactStyle is always "notch".
  property bool barStyleAvailable: false
  // Prefix for log lines.
  property string logName: svc.ipcTarget

  // -------------------------------------------------------------- built-ins
  readonly property var builtinModules: ({
    media: Qt.resolvedUrl("modules/media.qml"),
    activities: Qt.resolvedUrl("modules/activities.qml")
  })

  function moduleUrl(id) {
    if (svc.hostModules && svc.hostModules[id]) return svc.hostModules[id]
    return svc.builtinModules[id] || ""
  }

  // ---------------------------------------------------------------- config
  // The parsed config, so hosts can read their own keys from it.
  property var config: ({})
  property var moduleIds: ["media", "activities"]
  property int hoverOpenDelay: 120
  property int hoverCloseDelay: 300
  // Where the compact state lives: "bar" (in the host's bar indicator; the
  // notch only drops out to peek or expand) or "notch" (hanging under the
  // top edge all the time).
  property string configuredStyle: "bar"
  readonly property string compactStyle: svc.barStyleAvailable && svc.configuredStyle === "bar" ? "bar" : "notch"

  function loadConfig(text) {
    try {
      var cfg = JSON.parse(String(text || "{}"))
      svc.config = cfg
      if (Array.isArray(cfg.modules)) svc.moduleIds = cfg.modules.map(String)
      if (cfg.hoverOpenDelay !== undefined) svc.hoverOpenDelay = Math.max(0, Number(cfg.hoverOpenDelay) || 0)
      if (cfg.hoverCloseDelay !== undefined) svc.hoverCloseDelay = Math.max(0, Number(cfg.hoverCloseDelay) || 0)
      svc.configuredStyle = cfg.compactStyle === "notch" ? "notch" : "bar"
    } catch (e) {
      console.warn(svc.logName + ": " + svc.configPath + " is not valid JSON:", e)
    }
  }

  FileView {
    path: svc.configPath
    watchChanges: true
    printErrors: false
    onLoaded: svc.loadConfig(text())
    onFileChanged: reload()
  }

  // --------------------------------------------------------------- modules
  property var modules: []

  function rebuildModules() {
    var out = []
    for (var i = 0; i < moduleLoaders.count; i++) {
      var loader = moduleLoaders.itemAt(i)
      if (loader && loader.item) out.push(loader.item)
    }
    svc.modules = out
  }

  function moduleById(id) {
    for (var i = 0; i < svc.modules.length; i++)
      if (svc.modules[i].moduleId === id) return svc.modules[i]
    return null
  }

  Repeater {
    id: moduleLoaders
    model: svc.moduleIds
    delegate: Loader {
      required property string modelData
      source: svc.moduleUrl(modelData)
      onLoaded: {
        item.notch = svc
        if (item.moduleId === "") item.moduleId = modelData
        svc.rebuildModules()
      }
      onStatusChanged: if (status === Loader.Error) console.warn(svc.logName + ": module '" + modelData + "' failed to load")
      Component.onCompleted: if (String(source) === "") console.warn(svc.logName + ": unknown module '" + modelData + "'")
      Component.onDestruction: Qt.callLater(svc.rebuildModules)
    }
  }

  // Bindings read each module's `active` and `priority`, so they re-run when
  // any module changes state.
  readonly property var activeModules: {
    var out = []
    for (var i = 0; i < svc.modules.length; i++) {
      var m = svc.modules[i]
      if (m && m.active) out.push(m)
    }
    out.sort(function(a, b) { return b.priority - a.priority })
    return out
  }

  readonly property var compactModule: {
    for (var i = 0; i < svc.activeModules.length; i++)
      if (svc.activeModules[i].compact || svc.activeModules[i].barView) return svc.activeModules[i]
    return null
  }

  readonly property var expandedModules: svc.activeModules.filter(function(m) { return !!m.expanded })

  // ------------------------------------------------------------------ peek
  property var peekModule: null

  function requestPeek(module, ms) {
    if (!module || !module.peek || svc.pinned) return
    if (svc.hovered && !module.urgentPeek) return
    // A higher-priority peek on screen (the OSD) is not cut short by a
    // lower one (a track change).
    if (svc.peekModule && svc.peekModule !== module && peekTimer.running
        && svc.peekModule.priority > module.priority) return
    svc.peekModule = module
    peekTimer.interval = Math.max(400, Number(ms) || 2500)
    peekTimer.restart()
  }

  function dismissPeek(module) {
    if (!module || svc.peekModule === module) {
      peekTimer.stop()
      svc.peekModule = null
    }
  }

  Timer { id: peekTimer; onTriggered: svc.peekModule = null }

  // ----------------------------------------------------------------- hover
  // Several surfaces report the pointer (the notch card, one bar indicator
  // per monitor); the notch counts as hovered while any of them has it.
  property var pointerSources: ({})
  readonly property bool pointerInside: Object.keys(svc.pointerSources).length > 0
  property bool hovered: false
  property bool pinned: false

  // The monitor whose bar indicator opened the notch; the overlay follows it
  // while expanded instead of the focused monitor.
  property string screenOverride: ""

  function setPointer(source, inside, screenName) {
    var next = Object.assign({}, svc.pointerSources)
    if (inside) next[source] = true
    else delete next[source]
    svc.pointerSources = next
    if (inside && screenName) svc.screenOverride = screenName
  }

  onPointerInsideChanged: {
    if (pointerInside) { closeTimer.stop(); openTimer.restart() }
    else { openTimer.stop(); closeTimer.restart() }
  }
  onHoveredChanged: if (hovered && svc.peekModule && !svc.peekModule.urgentPeek) svc.dismissPeek()
  onPinnedChanged: if (pinned) svc.dismissPeek()
  onModeChanged: if (mode !== "expanded" && mode !== "peek") svc.screenOverride = ""

  Timer { id: openTimer; interval: svc.hoverOpenDelay; onTriggered: svc.hovered = true }
  Timer { id: closeTimer; interval: svc.hoverCloseDelay; onTriggered: svc.hovered = false }

  function open() { svc.pinned = true }
  function close() { svc.pinned = false; svc.hovered = false }
  function togglePinned(screenName) {
    if (screenName) svc.screenOverride = screenName
    svc.pinned = !svc.pinned
  }

  // ------------------------------------------------------------------ mode
  readonly property string mode: (svc.peekModule && !svc.pinned) ? "peek"
    : ((svc.pinned || svc.hovered) ? "expanded"
    : (svc.compactModule ? "compact" : "rest"))

  // ------------------------------------------------------------------- IPC
  IpcHandler {
    target: svc.ipcTarget
    function toggle(): void { svc.pinned = !svc.pinned }
    function open(): void { svc.open() }
    function close(): void { svc.close() }
    // Generic activities, for scripts: see modules/activities.qml.
    function push(json: string): string {
      var m = svc.moduleById("activities")
      return m ? m.push(json) : "activities module not loaded"
    }
    function clear(id: string): string {
      var m = svc.moduleById("activities")
      return m ? m.clear(id) : "activities module not loaded"
    }
    function state(): string {
      return JSON.stringify({
        mode: svc.mode,
        compactStyle: svc.compactStyle,
        peek: svc.peekModule ? svc.peekModule.moduleId : null,
        modules: svc.modules.map(function(m) { return { id: m.moduleId, active: m.active, priority: m.priority } })
      })
    }
  }
}
