import QtQuick
import Quickshell
import "Config.js" as Config
import "State.js" as State
import "Position.js" as Position

// One notch of the config's `notches` (or the top-level one): its modules,
// where it hangs and how. NotchService makes one per notch; it shows as
// copies (NotchCopy), which hold the state the pointer and peeks change,
// while this holds what they share:
//   following focus      one copy, which moves
//   kept on a screen     a copy per screen; the one where it hangs (its
//                        home, or where `workspaces` sends it) shows the
//                        closed notch, the others only peeks and the open
//                        notch, so a peek shows where you work without
//                        moving it
//   on every screen      ("all", and bar style) a copy per screen, each a
//                        notch of its own
Item {
  id: notch
  visible: false

  property var svc: null
  property string notchId: ""

  // ---------------------------------------------------------------- config
  // The resolved entry (Config.notches); keeps the last one while the id is
  // on its way out.
  readonly property var spec: notch.svc ? notch.svc.notchSpec(notch.notchId) : null
  readonly property int index: notch.spec ? notch.spec.index : 0
  readonly property var moduleIds: notch.spec ? notch.spec.moduleIds : []
  readonly property string configuredStyle: notch.spec ? notch.spec.compactStyle : Config.DEFAULTS.compactStyle
  // Where the compact state lives: "bar" (in the host's bar indicator; the
  // notch only drops out to peek or expand) or "notch" (hanging from its
  // edge all the time). One notch at most gets the bar (State.compactStyles).
  readonly property string compactStyle: notch.svc ? notch.svc.compactStyleAt(notch.index) : "notch"
  // Keep windows out of the strip the closed notch hangs into (compactStyle
  // "notch" only); NotchSurface reserves it.
  readonly property bool reserveSpace: !!notch.spec && notch.spec.reserveSpace
  // Workspaces the closed notch hangs on (ids or names); null: every one.
  readonly property var workspaces: notch.spec ? notch.spec.workspaces : null
  // The configured position, { edge, offset, screen } (Position.js).
  readonly property var position: Position.resolve(notch.spec ? notch.spec.position : undefined)
  // Where it is: bar style locks it to the middle of the bar.
  readonly property var placement: Position.effective(notch.position, notch.compactStyle, notch.svc ? notch.svc.barEdge : "top")
  readonly property string edge: notch.placement.edge
  readonly property bool vertical: Position.isVertical(notch.edge)
  // A copy on every screen, each showing the notch.
  readonly property bool everyScreen: notch.placement.screen === Position.ALL_SCREENS
  // Kept on one screen (its home), by name.
  readonly property bool homed: !notch.everyScreen && notch.placement.screen !== ""
  // Whether it can be dragged to another edge; never in bar style, where it
  // belongs to the bar.
  readonly property bool canDrag: !!notch.spec && notch.spec.draggable && notch.compactStyle === "notch"

  // The config key for one of this notch's keys: "position" at the top
  // level, "notches.<index>.position" in a list.
  function configKey(key) { return (notch.spec ? notch.spec.prefix : "") + key }
  function setValue(key, value) { if (notch.svc) notch.svc.setConfigValue(notch.configKey(key), value) }

  // Whether the closed notch hangs on `screen`, by the workspace it shows.
  // Bindings that call it follow workspace switches.
  function showsOn(screen) {
    var compositor = notch.svc ? notch.svc.compositor : null
    var ws = compositor && screen ? compositor.activeWorkspace(screen) : null
    return State.workspaceAllowed(notch.workspaces, ws)
  }

  // --------------------------------------------------------------- modules
  // Its modules, in its order, out of the ones the service loaded.
  readonly property var modules: {
    var out = []
    var loaded = notch.svc ? notch.svc.modules : []
    for (var i = 0; i < notch.moduleIds.length; i++)
      for (var j = 0; j < loaded.length; j++)
        if (loaded[j].moduleId === notch.moduleIds[i]) { out.push(loaded[j]); break }
    return out
  }
  function hasModule(module) { return !!module && notch.modules.indexOf(module) !== -1 }

  // State.js has the rules; bindings read each module's `active` and
  // `priority`, so they re-run when any module changes state.
  readonly property var activeModules: State.activeModules(notch.modules)
  readonly property var compactModule: State.compactModule(notch.activeModules)
  readonly property var expandedModules: notch.activeModules.filter(function(m) { return !!m.expanded })

  // ---------------------------------------------------------------- screens
  readonly property string focusedScreenName: notch.svc && notch.svc.compositor ? notch.svc.compositor.focusedScreenName : ""
  // Every screen, and whether its workspace takes the closed notch.
  readonly property var screenStates: {
    var screens = notch.svc ? notch.svc.screens : []
    var list = []
    for (var i = 0; i < screens.length; i++)
      list.push({ name: screens[i].name, allowed: notch.showsOn(screens[i]) })
    return list
  }
  // Where a notch kept on a screen hangs closed: its home, else where its
  // workspaces send it (State.notchScreen); "" for nowhere, or not kept.
  readonly property string hostScreen: !notch.homed ? "" : State.notchScreen({
    screens: notch.screenStates, focused: notch.focusedScreenName, open: false, home: notch.placement.screen
  })

  // ---------------------------------------------------------------- copies
  // Screen names, one copy each; [""] for the one copy that moves.
  readonly property bool perScreen: notch.everyScreen || notch.homed
  readonly property var copyScreens: notch.perScreen
    ? (notch.svc ? notch.svc.screens : []).map(function(s) { return s.name }) : [""]

  Variants {
    id: copyVariants
    readonly property var owner: notch
    model: notch.copyScreens
    NotchCopy {
      required property var modelData
      owner: copyVariants.owner
      fixedScreen: modelData
    }
  }
  readonly property var copies: copyVariants.instances

  // The copy on a screen; the one copy, for a notch that moves.
  function copyOn(screenName) {
    var list = notch.copies
    if (!notch.perScreen) return list.length > 0 ? list[0] : null
    for (var i = 0; i < list.length; i++) if (list[i].fixedScreen === screenName) return list[i]
    return null
  }

  // The copy that peeks or opens: the one on the focused screen, if there is
  // one per screen (State.peekCopy).
  function focusedCopy() {
    var name = State.peekCopy(notch.copyScreens, notch.focusedScreenName)
    return name === null ? null : notch.copyOn(name)
  }

  // ----------------------------------------------------------------- peeks
  // A module's peek, if this notch shows the module: on the focused copy,
  // and on the one where a notch kept on a screen hangs (State.peekCopies).
  function requestPeek(module, ms) {
    if (!notch.hasModule(module)) return
    var names = State.peekCopies(notch.copyScreens, notch.focusedScreenName, notch.hostScreen)
    for (var i = 0; i < names.length; i++) {
      var copy = notch.copyOn(names[i])
      if (copy) copy.requestPeek(module, ms)
    }
  }
  function dismissPeek(module) {
    for (var i = 0; i < notch.copies.length; i++) notch.copies[i].dismissPeek(module)
  }

  // ------------------------------------------------------------------ open
  function open() { var copy = notch.focusedCopy(); if (copy) copy.open() }
  function close() { for (var i = 0; i < notch.copies.length; i++) notch.copies[i].close() }
  function toggle() {
    for (var i = 0; i < notch.copies.length; i++)
      if (notch.copies[i].pinned) { notch.close(); return }
    notch.open()
  }
}
