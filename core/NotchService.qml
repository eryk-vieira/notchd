import QtQuick
import Quickshell
import Quickshell.Io
import "settings"
import "Config.js" as Config
import "State.js" as State
import "settings/Settings.js" as Settings

// The notches' source of truth: config, modules, the notches (Notch, one per
// entry of the config's `notches`, each shown as one or more NotchCopy) and
// IPC. Every surface that shows a notch (NotchSurface, a host's bar
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
  // The screen edge the host's bar is on ("top", "bottom", "left", "right").
  // In compactStyle "bar" the notch hangs from it.
  property string barEdge: "top"
  // Prefix for log lines.
  property string logName: svc.ipcTarget
  // A compositor adapter (HyprlandCompositor, GenericCompositor, ...): the
  // focused screen, fullscreen windows and which workspace each screen
  // shows, for the `workspaces` setting.
  property var compositor: null
  // The screens a notch can be on (anything with a `name`): Quickshell's.
  // Tests give their own, to have more than one.
  property var screens: Quickshell.screens || []
  // Modules to load when the config doesn't list any.
  property var defaultModules: ["media", "activities"]
  // Modules that show what the system does (the OSD): loaded whether a
  // notch lists them or not, so their peeks always show; where no notch on
  // the focused screen lists one, the default notch shows it, at the top.
  property var systemModules: []
  // Later: set while the service is being made, it would reassign the list
  // its own binding reads.
  onSystemModulesChanged: Qt.callLater(svc.refreshModuleIds)
  // Extra settings-window fields for the host's own config keys, in the
  // same format as coreSettingsSchema below.
  property var hostSettingsSchema: []
  // Extra settings-window pages, as corePages below. A page with a core
  // page's id replaces its label or icon.
  property var hostSettingsPages: []

  // -------------------------------------------------------------- built-ins
  readonly property var builtinModules: ({
    media: Qt.resolvedUrl("modules/media.qml"),
    activities: Qt.resolvedUrl("modules/activities.qml"),
    resources: Qt.resolvedUrl("modules/resources.qml")
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
  property int hoverOpenDelay: Config.DEFAULTS.hoverOpenDelay
  property int hoverCloseDelay: Config.DEFAULTS.hoverCloseDelay
  // Every notch, resolved (Config.notches), and their ids.
  property var notchSpecs: Config.notches({}, svc.defaultModules)
  property var notchIds: svc.notchSpecs.map(function(n) { return n.id })
  // Every module some notch shows, and the system ones: the ones to load.
  property var moduleIds: Config.moduleUnion(svc.notchSpecs, svc.systemModules)

  function sameList(a, b) { return JSON.stringify(a) === JSON.stringify(b) }
  function refreshModuleIds() {
    var modules = Config.moduleUnion(svc.notchSpecs, svc.systemModules)
    if (!svc.sameList(modules, svc.moduleIds)) svc.moduleIds = modules
  }

  // Keys missing from the config fall back to their defaults, so deleting a
  // key in the file (or the settings window) resets it. Config.resolve and
  // Config.notches have the rules. The id and module lists are only
  // replaced when they change: a new list would make every notch and module
  // again, losing what they show.
  function applyConfig(cfg) {
    var r = Config.resolve(cfg)
    var specs = Config.notches(cfg, svc.defaultModules)
    svc.config = cfg
    svc.hoverOpenDelay = r.hoverOpenDelay
    svc.hoverCloseDelay = r.hoverCloseDelay
    svc.notchSpecs = specs
    var ids = specs.map(function(n) { return n.id })
    if (!svc.sameList(ids, svc.notchIds)) svc.notchIds = ids
    var modules = Config.moduleUnion(specs, svc.systemModules)
    if (!svc.sameList(modules, svc.moduleIds)) svc.moduleIds = modules
  }

  function loadConfig(text) {
    // Our own pending edit is newer than whatever the file says right now.
    if (saveTimer.running) return
    var parsed = Config.parse(text)
    if (parsed.ok) svc.applyConfig(parsed.config)
    else console.warn(svc.logName + ": ignoring " + svc.configPath + ": " + parsed.error)
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
  function configValue(key) { return Config.valueAt(svc.config, key) }

  // Applies at once and writes the file shortly after, so dragging a slider
  // doesn't write on every step. `undefined` removes the key (back to its
  // default); emptied parent objects are removed too.
  function setConfigValue(key, value) {
    svc.replaceConfig(Config.withValue(svc.config, key, value))
  }

  // The whole config at once, applied and then written.
  function replaceConfig(cfg) {
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
    { id: "notch", label: "Notches", icon: 0xF0A66 },       // nf-md-puzzle_outline
    { id: "general", label: "General", icon: 0xF0493 },     // nf-md-cog
    { id: "appearance", label: "Appearance", icon: 0xF0E0C } // nf-md-palette_outline
  ]
  readonly property var settingsPages: Settings.mergePages(svc.corePages, svc.hostSettingsPages)

  // The fields the settings window shows, built from these descriptors:
  //   key        config key (dotted for nested objects)
  //   type       "choice" | "integer" | "boolean" | "string" | "color"
  //              | "modules" | "workspaces" | "notches" (the notch picker)
  //              | "note" (text only, no key)
  //   label, help
  //   page       sidebar page id (default "general")
  //   section    heading the field sits under, within its page
  //   default    value shown while the key is absent
  //   options    [{ value, label, preview }] for "choice"; `preview` is the
  //              url of a QML file drawn on the card (root takes `selected`)
  //   display    "cards" shows a choice as picture cards instead of segments
  //   min, max, step, unit   for "integer"
  //
  // A notch's own keys sit on the "notch" page, under its picker, and are
  // those of the notch the window edits (settingsNotch): in a list,
  // "notches.<index>.<key>", whose default is the top-level key it inherits.
  // "general" has what applies to every notch.
  readonly property var coreSettingsSchema: {
    var out = []
    var n = svc.settingsNotchObject
    var prefix = n && n.spec ? n.spec.prefix : ""
    function key(k) { return prefix + k }
    function inherited(k, fallback) {
      if (prefix === "") return fallback
      var v = Config.valueAt(svc.config, k)
      return v === undefined ? fallback : v
    }
    var style = n ? n.compactStyle : "notch"
    var several = svc.notches.length > 1

    out.push({ page: "notch", section: "Notch", key: "notches", type: "notches", label: "Notches",
               help: several ? "Pick the notch to set up below. Each has its own modules and place."
                             : "Add a notch to show other modules somewhere else, each with its own place." })
    if (prefix !== "")
      out.push({ page: "notch", section: "Notch", key: key("id"), type: "string", label: "Name",
                 default: Config.defaultNotchId(n.index),
                 help: "What IPC calls it: openNotch, closeNotch and toggleNotch take it." })
    out.push({ page: "notch", section: "Modules", key: key("modules"), type: "modules", label: "Loaded modules",
               default: inherited("modules", svc.defaultModules),
               help: (several ? "What this notch shows. A module may show in several notches. Their order breaks ties in the expanded view."
                              : "Switched-on modules load. Their order breaks ties in the expanded view.")
                     + svc.systemNote })
    // The bar holds one notch's compact state; another notch can't pick it
    // until that one hangs.
    var barOwner = svc.barNotch
    if (svc.barStyleAvailable && barOwner && n && barOwner !== n) {
      out.push({ page: "notch", section: "Layout", type: "note", label: "Compact style: hanging",
                 help: "The bar holds the compact state of " + barOwner.notchId + ", so this notch hangs from its edge. Set " + barOwner.notchId + " to the hanging notch to give the bar to this one." })
    } else if (svc.barStyleAvailable) {
      out.push({ page: "notch", section: "Layout", key: key("compactStyle"), type: "choice", display: "cards",
                 label: "Compact style", default: inherited("compactStyle", Config.DEFAULTS.compactStyle),
                 help: several ? "Where an active module lives when the notch is closed. The bar holds one notch at a time."
                               : "Where an active module lives when the notch is closed.",
                 options: [
                   { value: "bar", label: "In the bar", preview: Qt.resolvedUrl("settings/previews/CompactBar.qml") },
                   { value: "notch", label: "Hanging notch", preview: Qt.resolvedUrl("settings/previews/CompactNotch.qml") }
                 ] })
    }
    // Only a notch that hangs below the edge while closed has a strip to keep.
    if (style === "notch")
      out.push({ page: "notch", section: "Layout", key: key("reserveSpace"), type: "boolean",
                 label: "Keep windows clear", default: inherited("reserveSpace", Config.DEFAULTS.reserveSpace),
                 help: "Windows keep clear of the closed notch instead of going under it, along its whole edge: a sliver at rest, more while a module is active. Peeks and the open notch still cover them." })
    if (style === "notch") {
      out.push({ page: "notch", section: "Position", key: key("position.edge"), type: "choice", display: "cards",
                 label: "Edge", default: inherited("position.edge", "top"),
                 help: "The screen edge the notch hangs from. On a side edge, an active module without a vertical view shows a dot.",
                 options: ["top", "bottom", "left", "right"].map(function(e) {
                   return { value: e, label: e.charAt(0).toUpperCase() + e.slice(1),
                            preview: Qt.resolvedUrl("settings/previews/Edge.qml") }
                 }) })
      out.push({ page: "notch", section: "Position", key: key("position.offset"), type: "number", display: "percent",
                 label: "Along the edge", default: inherited("position.offset", 0.5), min: 0, max: 1, step: 0.01,
                 help: "Where on the edge: 0 % is its left (or top) end, 50 % the middle." })
      var screens = svc.screens
      if (screens.length > 1)
        out.push({ page: "notch", section: "Position", key: key("position.screen"), type: "choice",
                   label: "Screen", default: inherited("position.screen", ""),
                   help: "Where the notch stays. Following focus, it moves to the screen you work on. On a screen of its own, it stays there, peeks included; on a screen without a notch that shows it, a peek appears at the top. On every screen, each screen has its own copy, and a peek shows on the focused one.",
                   options: [{ value: "", label: "Follow focus" }, { value: "all", label: "Every screen" }].concat(screens.map(function(s) {
                     return { value: s.name, label: s.name }
                   })) })
      out.push({ page: "notch", section: "Position", key: key("draggable"), type: "boolean",
                 label: "Drag to move", default: inherited("draggable", Config.DEFAULTS.draggable),
                 help: "Hold the notch for a moment, then drag it to any edge of the screen; it snaps to the nearest one, and to the middle when close to it. A quick click only pins it." })
    } else {
      out.push({ page: "notch", section: "Position", type: "note", label: "Follows the bar",
                 help: "With the compact state in the bar, the notch drops out of the middle of the bar, on every screen. Pick the hanging notch to place it on any edge." })
    }
    if (svc.compositor && svc.compositor.supportsWorkspaces)
      out.push({ page: "notch", section: "Layout", key: key("workspaces"), type: "workspaces",
                 label: "Workspaces", default: inherited("workspaces", undefined),
                 help: "Where the closed notch (or its bar indicator) shows; none picked means every workspace. Peeks and the open notch show on any." })
    out.push({ page: "general", section: "Hover", key: "hoverOpenDelay", type: "integer", label: "Open delay",
               help: several ? "How long the pointer rests on a notch before it expands. For every notch."
                             : "How long the pointer rests on the notch before it expands.",
               default: Config.DEFAULTS.hoverOpenDelay, min: 0, max: 1000, step: 10, unit: "ms" })
    out.push({ page: "general", section: "Hover", key: "hoverCloseDelay", type: "integer", label: "Close delay",
               help: several ? "How long it stays open after the pointer leaves. For every notch."
                             : "How long it stays open after the pointer leaves.",
               default: Config.DEFAULTS.hoverCloseDelay, min: 0, max: 2000, step: 10, unit: "ms" })
    return out
  }
  readonly property var settingsSchema: svc.coreSettingsSchema
    .concat(Settings.moduleFields(svc.modules), svc.hostSettingsSchema || [])
  // The system modules, for the modules field's help.
  readonly property string systemNote: {
    if (!svc.systemModules || svc.systemModules.length === 0) return ""
    var names = svc.systemModules.map(function(id) {
      var m = svc.moduleById(id)
      return m && m.title ? m.title : id
    })
    return " " + names.join(", ") + " always " + (names.length > 1 ? "load" : "loads")
      + " and " + (names.length > 1 ? "show" : "shows") + " on the screen you work on: in a notch there that has it switched on, else in any notch there, else at the top."
  }

  property bool settingsOpen: false
  // The page the window shows; kept here so it survives closing the window.
  property string settingsPage: "notch"
  // The notch the window edits, by index.
  property int settingsNotch: 0
  readonly property var settingsNotchObject: svc.notches.length > 0
    ? svc.notches[Math.max(0, Math.min(svc.settingsNotch, svc.notches.length - 1))] : null
  // `index`: the notch to edit, if given; the window then shows its page.
  function openSettings(index) {
    if (typeof index === "number") {
      svc.settingsNotch = index
      svc.settingsPage = "notch"
    }
    svc.settingsOpen = true
  }
  function closeSettings() { svc.settingsOpen = false }

  // `svc: svc` would bind the window's own property to itself (the property
  // name shadows the id), so the reference goes through `owner`.
  LazyLoader {
    id: settingsLoader
    readonly property var owner: svc
    active: svc.settingsOpen
    SettingsWindow { svc: settingsLoader.owner }
  }

  // --------------------------------------------------------------- notches
  function notchSpec(id) {
    for (var i = 0; i < svc.notchSpecs.length; i++)
      if (svc.notchSpecs[i].id === id) return svc.notchSpecs[i]
    return null
  }

  // The compact style of the notch at `index`: only one gets the bar.
  readonly property var compactStyles: State.compactStyles(
    svc.notchSpecs.map(function(n) { return n.compactStyle }), svc.barStyleAvailable)
  function compactStyleAt(index) { return svc.compactStyles[index] || "notch" }

  // `notch: svc` would bind the notch's own property to itself (the property
  // name shadows the id), so the reference goes through `owner`.
  Variants {
    id: notchVariants
    readonly property var owner: svc
    model: svc.notchIds
    Notch {
      required property var modelData
      svc: notchVariants.owner
      notchId: modelData
    }
  }
  // The default notch: a notch of its own at the top of every screen, hidden
  // until it shows a peek where no notch with that module does
  // (State.needsVisitor, State.focusedPeek), such as a system module's
  // that no notch lists.
  Notch {
    id: visitorNotch
    // Through `owner`, as above.
    svc: notchVariants.owner
    visitor: true
    notchId: ""
  }
  readonly property var visitor: visitorNotch

  // The notches, in config order.
  readonly property var notches: {
    var list = notchVariants.instances.slice()
    list.sort(function(a, b) { return a.index - b.index })
    return list
  }
  // Every copy of every notch: what NotchSurface puts on screen.
  readonly property var copies: {
    var out = []
    for (var i = 0; i < svc.notches.length; i++) out = out.concat(svc.notches[i].copies)
    return out.concat(visitorNotch.copies)
  }
  // The first notch's first copy: what a single-notch view (the visual
  // tests, the README image) draws.
  readonly property var firstCopy: svc.copies.length > 0 ? svc.copies[0] : null
  // The notch whose compact state the host's bar holds, if any.
  readonly property var barNotch: {
    for (var i = 0; i < svc.notches.length; i++)
      if (svc.notches[i].compactStyle === "bar") return svc.notches[i]
    return null
  }

  function notchById(id) {
    for (var i = 0; i < svc.notches.length; i++)
      if (svc.notches[i].notchId === id) return svc.notches[i]
    return null
  }

  // A new notch in the config, off the edges the others hang from; and
  // taking one out (Config.withNotchAdded / withoutNotch). Returns the new
  // notch's index.
  function addNotch() {
    var used = svc.notches.map(function(n) { return n.edge })
    var edges = ["bottom", "left", "right", "top"].filter(function(e) { return used.indexOf(e) === -1 })
    var entry = { id: Config.freeNotchId(svc.notchIds), modules: [] }
    entry.position = { edge: edges.length > 0 ? edges[0] : "bottom" }
    var next = Config.withNotchAdded(svc.config, entry)
    svc.replaceConfig(next)
    return next.notches.length - 1
  }
  function removeNotch(index) { svc.replaceConfig(Config.withoutNotch(svc.config, index)) }

  // What modules read: whether any notch is open, and whether one shows
  // `module`'s peek.
  readonly property bool expanded: svc.copies.some(function(c) { return c.mode === "expanded" })
  function peeking(module) {
    return svc.copies.some(function(c) { return c.mode === "peek" && c.peekModule === module })
  }

  // A module's peek goes to every notch that shows the module (on the copy
  // on the focused screen of one that has a copy per screen), and to the
  // visitor when none of them peeks on the focused screen. A module that
  // peeks on the focused screen only (the OSD) peeks once: in the first
  // notch there that shows it, else in the visitor (State.focusedPeek). A
  // system module's peek, with no notch there showing it, borrows the first
  // notch there all the same, so the default notch never draws over it.
  function requestPeek(module, ms) {
    var places = []
    var owners = []
    for (var i = 0; i < svc.notches.length; i++) {
      if (!svc.notches[i].hasModule(module)) continue
      places.push(svc.notches[i].peekPlace())
      owners.push(svc.notches[i])
    }
    var focused = svc.compositor ? svc.compositor.focusedScreenName : ""
    var system = !!module && (svc.systemModules || []).indexOf(module.moduleId) !== -1
    if (module && (module.peekOnFocusedScreen || system)) {
      var at = State.focusedPeek(places, focused)
      if (at >= 0) { owners[at].requestPeek(module, ms); return }
      if (system && focused) {
        var any = State.focusedPeek(svc.notches.map(function(n) { return n.peekPlace() }), focused)
        if (any >= 0) { svc.notches[any].showPeek(module, ms); return }
      }
      visitorNotch.requestPeek(module, ms)
      return
    }
    for (var j = 0; j < owners.length; j++) owners[j].requestPeek(module, ms)
    if (State.needsVisitor(places, focused)) visitorNotch.requestPeek(module, ms)
  }
  function dismissPeek(module) {
    for (var i = 0; i < svc.notches.length; i++) svc.notches[i].dismissPeek(module)
    visitorNotch.dismissPeek(module)
  }

  // Without a notch named, open and toggle act on the first notch and close
  // closes them all.
  function open() { if (svc.notches.length > 0) svc.notches[0].open() }
  function close() { for (var i = 0; i < svc.notches.length; i++) svc.notches[i].close() }
  function toggle() { if (svc.notches.length > 0) svc.notches[0].toggle() }

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
        var module = item as NotchModule
        if (!module) { console.warn(svc.logName + ": module '" + modelData + "' is not a NotchModule"); return }
        module.notch = svc
        if (module.moduleId === "") module.moduleId = modelData
        svc.rebuildModules()
      }
      onStatusChanged: if (status === Loader.Error) console.warn(svc.logName + ": module '" + modelData + "' failed to load")
      Component.onCompleted: if (String(source) === "") console.warn(svc.logName + ": unknown module '" + modelData + "'")
      Component.onDestruction: Qt.callLater(svc.rebuildModules)
    }
  }

  // ------------------------------------------------------------------- IPC
  function ipcNotch(id) { return svc.notchById(id) }
  IpcHandler {
    target: svc.ipcTarget
    function toggle(): void { svc.toggle() }
    function open(): void { svc.open() }
    function close(): void { svc.close() }
    // The same for one notch, by id.
    function toggleNotch(id: string): string { var n = svc.ipcNotch(id); if (!n) return "no notch " + id; n.toggle(); return "ok" }
    function openNotch(id: string): string { var n = svc.ipcNotch(id); if (!n) return "no notch " + id; n.open(); return "ok" }
    function closeNotch(id: string): string { var n = svc.ipcNotch(id); if (!n) return "no notch " + id; n.close(); return "ok" }
    function settings(): void { svc.settingsOpen = !svc.settingsOpen }
    // Every notch back to the middle of the top edge, following focus, after
    // a drag that went astray.
    function recenter(): void {
      var cfg = Config.withValue(svc.config, "position", undefined)
      for (var i = 0; Config.hasNotchList(cfg) && i < cfg.notches.length; i++)
        cfg = Config.withValue(cfg, "notches." + i + ".position", undefined)
      svc.replaceConfig(cfg)
    }
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
        notches: svc.notches.map(function(n) {
          return {
            id: n.notchId,
            compactStyle: n.compactStyle,
            reserveSpace: n.reserveSpace,
            workspaces: n.workspaces,
            position: n.placement,
            draggable: n.canDrag,
            modules: n.modules.map(function(m) { return m.moduleId }),
            copies: n.copies.map(function(c) {
              return { screen: c.screenName, mode: c.mode, peek: c.peekModule ? c.peekModule.moduleId : null }
            })
          }
        }),
        // The visitor's copies that show something.
        visitor: visitorNotch.copies.filter(function(c) { return c.mode === "peek" || c.mode === "expanded" })
          .map(function(c) { return { screen: c.screenName, mode: c.mode, peek: c.peekModule ? c.peekModule.moduleId : null } }),
        modules: svc.modules.map(function(m) { return { id: m.moduleId, active: m.active, priority: m.priority } })
      })
    }
  }
}
