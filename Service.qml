import QtQuick
import Quickshell
import Quickshell.Io

// The notch's single source of truth, shared by the overlay under the bar
// (Notch.qml) and the bar indicator (BarIndicator.qml): config, modules,
// mode, peeks, hover and IPC. Modules see this object as `notch`.
Item {
  id: svc
  visible: false

  property var shell: null

  // ---------------------------------------------------------------- config
  readonly property string pluginDir: String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "").replace(/\/$/, "")
  property var moduleIds: ["osd", "media", "activities"]
  property int hoverOpenDelay: 120
  property int hoverCloseDelay: 300
  // Where the compact state lives: "bar" (an indicator in the bar; the notch
  // only drops below it to peek or expand) or "notch" (hanging under the
  // clock all the time).
  property string compactStyle: "bar"

  function loadConfig(text) {
    try {
      var cfg = JSON.parse(String(text || "{}"))
      if (Array.isArray(cfg.modules)) svc.moduleIds = cfg.modules.map(String)
      if (cfg.hoverOpenDelay !== undefined) svc.hoverOpenDelay = Math.max(0, Number(cfg.hoverOpenDelay) || 0)
      if (cfg.hoverCloseDelay !== undefined) svc.hoverCloseDelay = Math.max(0, Number(cfg.hoverCloseDelay) || 0)
      svc.compactStyle = cfg.compactStyle === "notch" ? "notch" : "bar"
    } catch (e) {
      console.warn("eryk.notch: config.json is not valid JSON:", e)
    }
  }

  FileView {
    path: svc.pluginDir + "/config.json"
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
      source: Qt.resolvedUrl("modules/" + modelData + ".qml")
      onLoaded: {
        item.notch = svc
        if (item.moduleId === "") item.moduleId = modelData
        svc.rebuildModules()
      }
      onStatusChanged: if (status === Loader.Error) console.warn("eryk.notch: module '" + modelData + "' failed to load")
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
    target: "eryk.notch"
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
