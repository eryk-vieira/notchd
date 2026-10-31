import QtQuick
import Quickshell
import Quickshell.Io
import "settings"

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
  // Absolute path of the JSON config. Watched; edits apply live. Defaults
  // to the user's config dir, so settings survive plugin updates and never
  // land in the source tree. A missing file means every key at its default.
  readonly property string defaultConfigPath: {
    var base = Quickshell.env("XDG_CONFIG_HOME") || (Quickshell.env("HOME") + "/.config")
    return base + "/notchd/config.json"
  }
  property string configPath: svc.defaultConfigPath
  // Extra modules the host ships, as { id: url }. They win over built-ins
  // with the same id.
  property var hostModules: ({})
  // Whether the host has a bar indicator that can hold the compact state.
  // Without one, compactStyle is always "notch".
  property bool barStyleAvailable: false
  // Prefix for log lines.
  property string logName: svc.ipcTarget
  // Modules to load when the config doesn't list any.
  property var defaultModules: ["media", "activities"]
  // Extra settings-window fields for the host's own config keys, in the
  // same format as coreSettingsSchema below.
  property var hostSettingsSchema: []
  // Extra settings-window pages, as corePages below. A page with a core
  // page's id replaces its label or icon.
  property var hostSettingsPages: []

  // -------------------------------------------------------------- built-ins
  readonly property var builtinModules: ({
    media: Qt.resolvedUrl("modules/media.qml"),
    activities: Qt.resolvedUrl("modules/activities.qml")
  })

  function moduleUrl(id) {
    if (svc.hostModules && svc.hostModules[id]) return svc.hostModules[id]
    return svc.builtinModules[id] || ""
  }

  // Every module this host can load, built-ins first.
  readonly property var availableModuleIds: {
    var out = Object.keys(svc.builtinModules)
    var host = Object.keys(svc.hostModules || {})
    for (var i = 0; i < host.length; i++)
      if (out.indexOf(host[i]) === -1) out.push(host[i])
    return out
  }

  // ---------------------------------------------------------------- config
  // The parsed config, so hosts can read their own keys from it.
  property var config: ({})
  property var moduleIds: svc.defaultModules
  property int hoverOpenDelay: 120
  property int hoverCloseDelay: 300
  // Where the compact state lives: "bar" (in the host's bar indicator; the
  // notch only drops out to peek or expand) or "notch" (hanging under the
  // top edge all the time).
  property string configuredStyle: "bar"
  readonly property string compactStyle: svc.barStyleAvailable && svc.configuredStyle === "bar" ? "bar" : "notch"

  // Keys missing from the config fall back to their defaults, so deleting a
  // key in the file (or the settings window) resets it.
  function applyConfig(cfg) {
    svc.config = cfg
    svc.moduleIds = Array.isArray(cfg.modules) ? cfg.modules.map(String) : svc.defaultModules
    svc.hoverOpenDelay = cfg.hoverOpenDelay === undefined ? 120 : Math.max(0, Number(cfg.hoverOpenDelay) || 0)
    svc.hoverCloseDelay = cfg.hoverCloseDelay === undefined ? 300 : Math.max(0, Number(cfg.hoverCloseDelay) || 0)
    svc.configuredStyle = cfg.compactStyle === "notch" ? "notch" : "bar"
  }

  function loadConfig(text) {
    // Our own pending edit is newer than whatever the file says right now.
    if (saveTimer.running) return
    try {
      var cfg = JSON.parse(String(text || "{}"))
      svc.applyConfig(cfg && typeof cfg === "object" && !Array.isArray(cfg) ? cfg : {})
    } catch (e) {
      console.warn(svc.logName + ": " + svc.configPath + " is not valid JSON:", e)
    }
  }

  FileView {
    id: configFile
    path: svc.configPath
    watchChanges: true
    printErrors: false
    onLoaded: { missingConfigRetry.stop(); svc.loadConfig(text()); svc.configResolved = true }
    onLoadFailed: { missingConfigRetry.start(); svc.configResolved = true }
    onFileChanged: reload()
    onSaveFailed: function(error) { console.warn(svc.logName + ": could not write " + svc.configPath + ": " + error) }
    // A file that didn't exist when the view loaded isn't watched yet; a
    // reload after the first save starts watching it.
    onSaved: reload()
  }

  // While the file is missing, look again now and then, so creating it by
  // hand is picked up without a restart.
  Timer {
    id: missingConfigRetry
    interval: 2000
    repeat: true
    onTriggered: configFile.reload()
  }

  // ------------------------------------------------------- config editing
  // Dotted keys reach into objects: "theme.foreground".
  function configValue(key) {
    var parts = String(key).split(".")
    var node = svc.config
    for (var i = 0; i < parts.length; i++) {
      if (!node || typeof node !== "object") return undefined
      node = node[parts[i]]
    }
    return node
  }

  // Applies at once and writes the file shortly after, so dragging a slider
  // doesn't write on every step. `undefined` removes the key (back to its
  // default); emptied parent objects are removed too.
  function setConfigValue(key, value) {
    var cfg = JSON.parse(JSON.stringify(svc.config || {}))
    var parts = String(key).split(".")
    var chain = [cfg]
    var node = cfg
    for (var i = 0; i < parts.length - 1; i++) {
      if (!node[parts[i]] || typeof node[parts[i]] !== "object") {
        if (value === undefined) return
        node[parts[i]] = {}
      }
      node = node[parts[i]]
      chain.push(node)
    }
    var leaf = parts[parts.length - 1]
    if (value === undefined) delete node[leaf]
    else node[leaf] = value
    for (var j = chain.length - 1; j > 0; j--)
      if (Object.keys(chain[j]).length === 0) delete chain[j - 1][parts[j - 1]]
    svc.applyConfig(cfg)
    saveTimer.restart()
  }

  Timer {
    id: saveTimer
    interval: 250
    onTriggered: {
      // The config dir may not exist yet on the first save.
      ensureConfigDir.command = ["mkdir", "-p", svc.configPath.replace(/\/[^\/]*$/, "")]
      ensureConfigDir.running = true
    }
  }

  Process {
    id: ensureConfigDir
    onExited: function(code) {
      if (code !== 0) console.warn(svc.logName + ": could not create the config dir for " + svc.configPath)
      configFile.setText(JSON.stringify(svc.config, null, 2) + "\n")
    }
  }

  // --------------------------------------------------------------- settings
  // Sidebar pages of the settings window, in order. A page shows only when
  // some field is on it.
  //   id, label
  //   icon       Nerd Font code point (or glyph string)
  readonly property var corePages: [
    { id: "general", label: "General", icon: 0xF0493 },     // nf-md-cog
    { id: "modules", label: "Modules", icon: 0xF0A66 },     // nf-md-puzzle_outline
    { id: "appearance", label: "Appearance", icon: 0xF0E0C } // nf-md-palette_outline
  ]
  readonly property var settingsPages: {
    var out = svc.corePages.map(function(p) { return Object.assign({}, p) })
    var host = svc.hostSettingsPages || []
    for (var i = 0; i < host.length; i++) {
      var at = out.findIndex(function(p) { return p.id === host[i].id })
      if (at === -1) out.push(host[i])
      else out[at] = Object.assign(out[at], host[i])
    }
    return out
  }

  // The fields the settings window shows, built from these descriptors:
  //   key        config key (dotted for nested objects)
  //   type       "choice" | "integer" | "boolean" | "string" | "color"
  //              | "modules" | "note" (text only, no key)
  //   label, help
  //   page       sidebar page id (default "general")
  //   section    heading the field sits under, within its page
  //   default    value shown while the key is absent
  //   options    [{ value, label, preview }] for "choice"; `preview` is the
  //              url of a QML file drawn on the card (root takes `selected`)
  //   display    "cards" shows a choice as picture cards instead of segments
  //   min, max, step, unit   for "integer"
  readonly property var coreSettingsSchema: {
    var out = []
    if (svc.barStyleAvailable)
      out.push({ page: "general", section: "Layout", key: "compactStyle", type: "choice", display: "cards",
                 label: "Compact style", default: "bar",
                 help: "Where an active module lives when the notch is closed.",
                 options: [
                   { value: "bar", label: "In the bar", preview: Qt.resolvedUrl("settings/previews/CompactBar.qml") },
                   { value: "notch", label: "Hanging notch", preview: Qt.resolvedUrl("settings/previews/CompactNotch.qml") }
                 ] })
    out.push({ page: "general", section: "Hover", key: "hoverOpenDelay", type: "integer", label: "Open delay",
               help: "How long the pointer rests on the notch before it expands.",
               default: 120, min: 0, max: 1000, step: 10, unit: "ms" })
    out.push({ page: "general", section: "Hover", key: "hoverCloseDelay", type: "integer", label: "Close delay",
               help: "How long it stays open after the pointer leaves.",
               default: 300, min: 0, max: 2000, step: 10, unit: "ms" })
    out.push({ page: "modules", key: "modules", type: "modules", label: "Loaded modules",
               default: svc.defaultModules,
               help: "Switched-on modules load. Their order breaks ties in the expanded view." })
    return out
  }
  readonly property var settingsSchema: svc.coreSettingsSchema.concat(svc.hostSettingsSchema || [])

  property bool settingsOpen: false
  // The page the window shows; kept here so it survives closing the window.
  property string settingsPage: "general"
  function openSettings() { svc.settingsOpen = true }
  function closeSettings() { svc.settingsOpen = false }

  // `svc: svc` would bind the window's own property to itself (the property
  // name shadows the id), so the reference goes through `owner`.
  LazyLoader {
    id: settingsLoader
    readonly property var owner: svc
    active: svc.settingsOpen
    SettingsWindow { svc: settingsLoader.owner }
  }

  // --------------------------------------------------------------- modules
  property var modules: []
  // Modules load once the config is read (or known to be missing), so they
  // are not created from the defaults and then again from the config.
  property bool configResolved: false

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
    model: svc.configResolved ? svc.moduleIds : []
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
    function settings(): void { svc.settingsOpen = !svc.settingsOpen }
    // Change one config key, as the settings window does. `value` is JSON
    // ("200", "\"notch\"", "[\"media\"]"); empty resets the key to its default.
    function set(key: string, value: string): string {
      if (!key) return "usage: set <key> <json value>"
      if (value === "") { svc.setConfigValue(key, undefined); return "ok" }
      try { svc.setConfigValue(key, JSON.parse(value)) } catch (e) { return "not JSON: " + value }
      return "ok"
    }
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
